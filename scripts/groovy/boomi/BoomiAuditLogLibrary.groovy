package boomi

@Grab('org.mongodb:mongodb-driver-sync:5.1.2')
@Grab('software.amazon.awssdk:secretsmanager:2.25.48')

import com.mongodb.ConnectionString
import com.mongodb.MongoClientSettings
import com.mongodb.MongoException
import com.mongodb.MongoSocketException
import com.mongodb.MongoTimeoutException
import com.mongodb.WriteConcern
import com.mongodb.client.MongoClient
import com.mongodb.client.MongoClients
import org.bson.Document

import software.amazon.awssdk.core.SdkBytes
import software.amazon.awssdk.regions.Region
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest

import boomi.BoomiOtelLibrary

import groovy.json.JsonSlurper

import java.util.Base64
import java.util.Date
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.text.SimpleDateFormat

/**
 * Boomi-facing audit log writer.
 *
 * Canonical record contract: docs/references/audit-log-contract.md, which
 * mirrors the production `AuditLogEntry` Pydantic model in `oms-backend`
 * (`apps/core/schemas.py`). Only `action`, `resource_type`, and `meta`
 * (with `meta.method`/`meta.path`/`meta.status`) are required; every other
 * field -- `trace_id`, `ip`, `error_code`, `resource_id`, `user_id`,
 * `impersonator_id`, `message`, `tpl_message`, `resource_changes` -- is
 * optional. This library owns MongoDB connection resolution, the fixed
 * database/collection, retries, timeouts, and `time` generation. It THROWS
 * on any failure so the calling Boomi process decides how to react (retry,
 * alert, halt); there is no fail-soft variant. See "Write Failure Handling"
 * in the contract.
 *
 * This class deliberately knows nothing about OpenTelemetry internals --
 * trace-ID correlation and write-failure telemetry are delegated entirely
 * to {@link BoomiOtelLibrary}, a separate, standalone library with no
 * knowledge of MongoDB or the audit-log contract. See
 * docs/references/boomi-groovy-library-architecture.md for why these are
 * two classes instead of one.
 */
class BoomiAuditLogLibrary {

  // Identifies this component's telemetry in SigNoz (the OTel `service.name`).
  private static final String SERVICE_NAME = 'oms-audit-writer'

  // Fixed write target -- callers never supply this.
  private static final String DB_NAME = 'oms_audit'
  private static final String COLLECTION_NAME = 'auditlogs'

  // Default Kubernetes Secret location for the MongoDB URI. The Boomi
  // process owner never needs to set these; override only for advanced/test
  // scenarios via the BOOMI_AUDIT_* environment variables in resolveMongoUri().
  private static final String DEFAULT_K8S_NAMESPACE = 'mongodb'
  private static final String DEFAULT_K8S_SECRET_NAME = 'oms-audit-writer'
  private static final String DEFAULT_K8S_SECRET_KEY = 'mongoUri'

  // Fields the contract requires from the caller. trace_id, ip, and time are
  // optional -- this library fills them in when absent. meta is required but
  // is validated separately (its own method/path/status must be present).
  private static final List<String> REQUIRED_FIELDS = [
    'action', 'resource_type', 'meta'
  ]

  private static final List<String> REQUIRED_META_FIELDS = [
    'method', 'path', 'status'
  ]

  private static final List<String> TIME_PATTERNS = [
    "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
    "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
    "yyyy-MM-dd'T'HH:mm:ssXXX",
    "yyyy-MM-dd'T'HH:mm:ss'Z'"
  ]

  // One pooled MongoClient per distinct URI, reused across calls instead of
  // creating/closing a client (and its connection pool) on every write.
  private static final Map<String, MongoClient> CLIENT_CACHE = new ConcurrentHashMap<>()

  // ---------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------

  /**
   * Writes one audit log document per docs/references/audit-log-contract.md.
   *
   * The caller must supply `action` (`{resource_type}.{verb}`) and
   * `resource_type`. `meta` ([method: ..., path: ..., status: ...]) is
   * required in the persisted document but may be omitted by the caller --
   * this method then defaults it to `[method: 'BOOMI', path: action,
   * status: (error_code ? 500 : 200)]`, since Boomi processes don't field
   * HTTP requests. Every other field is optional: `error_code`,
   * `resource_id`, `user_id`, `impersonator_id`, `message`, `tpl_message`
   * ([key: ..., params: [...]]), and `resource_changes` ([field: [old,
   * new]]) may be omitted or `null`.
   * `trace_id`, `ip`, and `time` are also optional -- omit them and this
   * method fills them in: `trace_id` reuses an active OpenTelemetry span's
   * trace ID when one exists, otherwise a fresh UUID; `ip` defaults to
   * `null`; `time` defaults to the current UTC time as a native BSON Date.
   * If `time` is supplied as an ISO-8601 String, it is parsed into that same
   * native Date -- this library generates the BSON Date itself so `time` is
   * always natively indexable/range-queryable in MongoDB, never a plain
   * string.
   *
   * This method THROWS on any failure -- a contract validation error, a
   * MongoDB connection problem, or an exhausted retry -- after emitting
   * best-effort critical telemetry to SigNoz via the OpenTelemetry Logs SDK
   * (and recording the exception on the active span, if any). There is no
   * fail-soft variant; the calling Boomi/OMS process is responsible for
   * deciding how to react.
   *
   * @return a Map with insertedId, trace_id, and time (the resolved values)
   */
  static Map<String, Object> writeAuditLog(Map<String, Object> event) {
    Map<String, Object> record = prepareRecord(event)

    try {
      validateRecord(record)
    } catch (IllegalArgumentException e) {
      emitFailureTelemetry(record, 'validation', e.message, e)
      throw e
    }

    String mongoUri
    try {
      mongoUri = resolveMongoUri()
    } catch (Exception e) {
      emitFailureTelemetry(record, 'configuration', e.message, e)
      throw new RuntimeException("Unable to resolve MongoDB connection: ${e.message}", e)
    }

    try {
      String insertedId = attemptWrite(mongoUri, record)
      return [insertedId: insertedId, trace_id: record.trace_id, time: record.time]
    } catch (Exception e) {
      emitFailureTelemetry(record, 'mongo_write', e.message, e)
      throw e
    }
  }

  /**
   * Closes and clears all pooled MongoClients and shuts down the
   * OpenTelemetry logger provider (via {@link BoomiOtelLibrary#shutdown}).
   * Call this from short-lived batch jobs or tests that need a clean
   * shutdown; not required for long-running Boomi runtimes, which should
   * keep reusing the pooled connection/provider.
   */
  static void closeAllClients() {
    CLIENT_CACHE.values().each { it.close() }
    CLIENT_CACHE.clear()
    BoomiOtelLibrary.shutdown()
  }

  // ---------------------------------------------------------------------
  // Record preparation -- fills trace_id / ip / error_code / time, never
  // overwrites a caller-supplied value.
  // ---------------------------------------------------------------------

  private static Map<String, Object> prepareRecord(Map<String, Object> event) {
    if (event == null) {
      throw new IllegalArgumentException('event must not be null')
    }
    Map<String, Object> record = new LinkedHashMap<String, Object>(event)
    if (isBlank(record.trace_id)) {
      record.trace_id = BoomiOtelLibrary.currentTraceId() ?: UUID.randomUUID().toString()
    }
    if (!record.containsKey('ip')) {
      record.ip = null
    }
    if (!record.containsKey('error_code')) {
      record.error_code = null
    }
    if (!record.containsKey('resource_id')) {
      record.resource_id = null
    }
    if (!record.containsKey('user_id')) {
      record.user_id = null
    }
    if (!record.containsKey('impersonator_id')) {
      record.impersonator_id = null
    }
    if (!record.containsKey('message')) {
      record.message = null
    }
    if (!record.containsKey('tpl_message')) {
      record.tpl_message = null
    }
    if (!record.containsKey('resource_changes')) {
      record.resource_changes = null
    }
    if (record.meta == null) {
      // meta is required in the persisted document (the production
      // AuditLogEntry model has no default for it), but Boomi processes
      // don't field HTTP requests, so a caller that omits meta entirely
      // gets a sensible default rather than a validation failure. A caller
      // that wants a more specific method/path/status supplies its own
      // meta Map instead -- see "meta For Non-HTTP Producers" in the
      // contract.
      record.meta = [
        method: 'BOOMI',
        path: record.action,
        status: isBlank(record.error_code) ? 200 : 500
      ]
    }
    record.time = resolveEventTime(record.time)
    return record
  }

  /**
   * Resolves `time` to a native java.util.Date, which the MongoDB driver
   * stores as a proper BSON Date -- never a string -- so `time` is natively
   * indexable and range-queryable. The library generates this itself; a
   * caller never constructs the date object by hand.
   */
  private static Date resolveEventTime(Object value) {
    if (value == null) {
      return new Date()
    }
    if (value instanceof Date) {
      return (Date) value
    }
    if (value instanceof String) {
      String normalized = value.trim()
      for (String pattern : TIME_PATTERNS) {
        try {
          SimpleDateFormat fmt = new SimpleDateFormat(pattern)
          fmt.setTimeZone(TimeZone.getTimeZone('UTC'))
          // Strict parsing: without this, SimpleDateFormat silently rolls
          // an out-of-range component (for example month 13, or day 32)
          // over into the next unit instead of rejecting the input.
          fmt.setLenient(false)
          return fmt.parse(normalized)
        } catch (java.text.ParseException ignored) {
          // try the next pattern
        }
      }
      throw new IllegalArgumentException("time must be a valid ISO-8601 UTC timestamp, got: ${value}")
    }
    throw new IllegalArgumentException("time must be null, a Date, or an ISO-8601 String, got: ${value.getClass()}")
  }

  // ---------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------

  private static void validateRecord(Map<String, Object> record) {
    List<String> missing = REQUIRED_FIELDS.findAll { isBlank(record?.get(it)) }
    if (missing) {
      throw new IllegalArgumentException("Audit record is missing required field(s): ${missing.join(', ')}")
    }

    Object meta = record.meta
    if (!(meta instanceof Map)) {
      throw new IllegalArgumentException('meta must be a Map with method, path, and status')
    }
    List<String> missingMeta = REQUIRED_META_FIELDS.findAll { isBlank(((Map) meta)?.get(it)) }
    if (missingMeta) {
      throw new IllegalArgumentException("meta is missing required field(s): ${missingMeta.join(', ')}")
    }

    Object tplMessage = record.tpl_message
    if (tplMessage != null) {
      if (!(tplMessage instanceof Map) || !((Map) tplMessage).containsKey('key')) {
        throw new IllegalArgumentException('tpl_message, when present, must be a Map with at least "key"')
      }
    }

    Object actionValue = record.action
    Object resourceTypeValue = record.resource_type
    if (actionValue instanceof String && resourceTypeValue instanceof String) {
      if (!((String) actionValue).startsWith(((String) resourceTypeValue) + '.')) {
        throw new IllegalArgumentException("action '${actionValue}' must start with resource_type '${resourceTypeValue}.'")
      }
    }
  }

  private static boolean isBlank(Object value) {
    return value == null || value.toString().trim().isEmpty()
  }

  // ---------------------------------------------------------------------
  // MongoDB URI resolution -- internal. writeAuditLog() calls this
  // automatically; the Boomi process owner never needs to.
  // ---------------------------------------------------------------------

  /**
   * Resolves the MongoDB connection URI. Exposed publicly only for
   * diagnostics/tooling (for example, printing the resolved URI for a manual
   * mongosh session) -- {@link #writeAuditLog} resolves it automatically.
   *
   * Resolution order: `BOOMI_AUDIT_MONGO_URI` env var, then
   * `BOOMI_AUDIT_AWS_SECRET_ID` env var (AWS Secrets Manager), then the
   * Kubernetes Secret `oms-audit-writer` in namespace `mongodb` (overridable
   * via `BOOMI_AUDIT_K8S_NAMESPACE` / `BOOMI_AUDIT_K8S_SECRET_NAME` /
   * `BOOMI_AUDIT_K8S_SECRET_KEY`), then a local dev fallback with a warning.
   */
  static String resolveMongoUri() {
    String explicit = System.getProperty('BOOMI_AUDIT_MONGO_URI') ?: System.getenv('BOOMI_AUDIT_MONGO_URI')
    if (!isBlank(explicit)) {
      return explicit
    }

    String awsSecretId = System.getProperty('BOOMI_AUDIT_AWS_SECRET_ID') ?: System.getenv('BOOMI_AUDIT_AWS_SECRET_ID')
    if (!isBlank(awsSecretId)) {
      String region = System.getProperty('AWS_REGION') ?: System.getenv('AWS_REGION') ?: 'ap-east-1'
      return extractMongoUriFromSecretPayload(readAwsSecretString(awsSecretId, region))
    }

    String namespace = System.getProperty('BOOMI_AUDIT_K8S_NAMESPACE') ?: System.getenv('BOOMI_AUDIT_K8S_NAMESPACE') ?: DEFAULT_K8S_NAMESPACE
    String secretName = System.getProperty('BOOMI_AUDIT_K8S_SECRET_NAME') ?: System.getenv('BOOMI_AUDIT_K8S_SECRET_NAME') ?: DEFAULT_K8S_SECRET_NAME
    String secretKey = System.getProperty('BOOMI_AUDIT_K8S_SECRET_KEY') ?: System.getenv('BOOMI_AUDIT_K8S_SECRET_KEY') ?: DEFAULT_K8S_SECRET_KEY
    try {
      return readKubernetesSecretValue(namespace, secretName, secretKey)
    } catch (Exception e) {
      // Never include credentials in this message.
      System.err.println(
        "WARNING: BoomiAuditLogLibrary could not read Secret ${namespace}/${secretName} " +
        "(${e.message}); falling back to local dev default 'mongodb://127.0.0.1:27017/?directConnection=true'. " +
        'Set BOOMI_AUDIT_MONGO_URI, or ensure the Kubernetes secret exists, in production.'
      )
      return 'mongodb://127.0.0.1:27017/?directConnection=true'
    }
  }

  static String readKubernetesSecretValue(String namespace, String secretName, String secretKey) {
    List<String> cmd = [
      'kubectl',
      '-n', namespace,
      'get', 'secret', secretName,
      '-o', "jsonpath={.data['${secretKey}']}"
    ]

    Process process = new ProcessBuilder(cmd)
      .redirectErrorStream(true)
      .start()

    String output = process.inputStream.getText('UTF-8').trim()
    int exitCode = process.waitFor()

    if (exitCode != 0) {
      throw new RuntimeException("Failed to read Kubernetes secret ${namespace}/${secretName}:${secretKey}. Output: ${output}")
    }

    if (!output) {
      throw new RuntimeException("Secret key '${secretKey}' not found in ${namespace}/${secretName}")
    }

    return new String(Base64.decoder.decode(output), 'UTF-8')
  }

  static String readAwsSecretString(String secretId, String awsRegion) {
    SecretsManagerClient client = SecretsManagerClient.builder()
      .region(Region.of(awsRegion))
      .build()

    try {
      def req = GetSecretValueRequest.builder()
        .secretId(secretId)
        .build()

      def res = client.getSecretValue(req)
      if (res.secretString()) {
        return res.secretString()
      }

      SdkBytes bin = res.secretBinary()
      if (bin != null) {
        return new String(bin.asByteArray(), 'UTF-8')
      }

      throw new RuntimeException("Secret '${secretId}' has neither secretString nor secretBinary")
    } finally {
      client.close()
    }
  }

  static String extractMongoUriFromSecretPayload(String payload) {
    if (!payload) {
      throw new RuntimeException('Secret payload is empty')
    }

    String trimmed = payload.trim()
    if (trimmed.startsWith('{')) {
      Map<String, Object> parsed = (Map<String, Object>) new JsonSlurper().parseText(trimmed)
      // Explicit blank checks (not Groovy truthy `?:`) so an accidental empty-string
      // value for one key doesn't silently fall through to the next key.
      List<String> candidateKeys = ['mongoUri', 'mongodbUri', 'uri', 'MONGO_URI']
      String candidate = null
      for (String key : candidateKeys) {
        if (!isBlank(parsed[key])) {
          candidate = parsed[key].toString()
          break
        }
      }
      if (!candidate) {
        throw new RuntimeException('Secret JSON does not contain a non-empty mongoUri/mongodbUri/uri/MONGO_URI key')
      }
      return candidate
    }

    return trimmed
  }

  /**
   * Redacts username/password from a MongoDB URI for safe logging.
   * Never log a raw mongoUri -- it contains credentials.
   */
  static String redactUri(String mongoUri) {
    if (!mongoUri) {
      return mongoUri
    }
    return mongoUri.replaceFirst('://[^@/]+@', '://***:***@')
  }

  // ---------------------------------------------------------------------
  // MongoDB write path (pooled client, bounded retry for transient errors)
  // ---------------------------------------------------------------------

  private static MongoClient getOrCreateClient(String mongoUri) {
    return CLIENT_CACHE.computeIfAbsent(mongoUri, { String uri ->
      MongoClientSettings settings = MongoClientSettings.builder()
        .writeConcern(WriteConcern.MAJORITY)
        .retryWrites(true)
        .applyToClusterSettings({ builder -> builder.serverSelectionTimeout(5000, TimeUnit.MILLISECONDS) })
        .applyToSocketSettings({ builder ->
          builder.connectTimeout(5000, TimeUnit.MILLISECONDS)
          builder.readTimeout(8000, TimeUnit.MILLISECONDS)
        })
        // Applied last so any parameter explicitly present in the URI (for
        // example a caller-specified w=1 or timeout) takes precedence over
        // the defaults above.
        .applyConnectionString(new ConnectionString(uri))
        .build()
      return MongoClients.create(settings)
    })
  }

  private static boolean isRetryableException(Throwable e) {
    if (e instanceof MongoTimeoutException || e instanceof MongoSocketException) {
      return true
    }
    if (e instanceof MongoException) {
      return ((MongoException) e).hasErrorLabel('RetryableWriteError')
    }
    return false
  }

  /**
   * Inserts the record, retrying a bounded number of times for transient
   * connection/timeout errors only (never for validation or a MongoDB write
   * error such as a duplicate key). Returns the inserted document's hex id,
   * or throws after retries are exhausted.
   */
  private static String attemptWrite(String mongoUri, Map<String, Object> record) {
    MongoClient client = getOrCreateClient(mongoUri)
    int maxRetries = 2
    long backoffMs = 250

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        def collection = client.getDatabase(DB_NAME).getCollection(COLLECTION_NAME)
        def insertResult = collection.insertOne(new Document(record))
        def insertedId = insertResult.getInsertedId()
        return insertedId?.asObjectId()?.value?.toHexString()
      } catch (Exception e) {
        boolean retryable = isRetryableException(e)
        boolean isLastAttempt = attempt == maxRetries
        if (isLastAttempt || !retryable) {
          throw new RuntimeException("Audit write failed: ${redactUri(e.message)}", e)
        }
        try {
          Thread.sleep(backoffMs * (long) Math.pow(2, attempt))
        } catch (InterruptedException ie) {
          // Restore the interrupt flag (standard practice) and treat this as
          // a terminal failure instead of letting InterruptedException
          // escape silently swallowed.
          Thread.currentThread().interrupt()
          throw new RuntimeException('Audit write retry was interrupted', ie)
        }
      }
    }
    // Unreachable -- every loop iteration above returns or throws.
    throw new RuntimeException('Audit write failed for an unknown reason')
  }

  // ---------------------------------------------------------------------
  // Failure telemetry (best-effort; must never mask the real exception)
  // ---------------------------------------------------------------------

  /**
   * Reports a critical, sanitized failure to SigNoz before the caller sees
   * the exception, per "Write Failure Handling" in the contract. All of the
   * actual OpenTelemetry work (building the logger, emitting the log
   * record, recording the exception on the active span) lives in
   * {@link BoomiOtelLibrary#emitCriticalFailure} -- this method is just a
   * thin call into that library with this class's `service.name` and the
   * record's `trace_id`. Best-effort: {@link BoomiOtelLibrary} swallows its
   * own errors internally, so this can never replace or hide the real
   * validation/write failure.
   */
  private static void emitFailureTelemetry(Map<String, Object> record, String failureType, String message, Throwable cause = null) {
    BoomiOtelLibrary.emitCriticalFailure(SERVICE_NAME, failureType, message, record?.trace_id?.toString(), cause)
  }
}
