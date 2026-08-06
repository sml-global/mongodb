package boomi

@Grab('io.opentelemetry:opentelemetry-api:1.51.0')
@Grab('io.opentelemetry:opentelemetry-sdk:1.51.0')
@Grab('io.opentelemetry:opentelemetry-exporter-otlp:1.51.0')

import io.opentelemetry.api.common.Attributes
import io.opentelemetry.api.common.AttributesBuilder
import io.opentelemetry.api.logs.Logger
import io.opentelemetry.api.logs.Severity
import io.opentelemetry.api.trace.Span
import io.opentelemetry.api.trace.SpanContext
import io.opentelemetry.api.trace.StatusCode
import io.opentelemetry.api.trace.Tracer
import io.opentelemetry.api.trace.propagation.W3CTraceContextPropagator
import io.opentelemetry.context.Context
import io.opentelemetry.context.Scope
import io.opentelemetry.context.propagation.TextMapGetter
import io.opentelemetry.context.propagation.TextMapPropagator
import io.opentelemetry.context.propagation.TextMapSetter
import io.opentelemetry.exporter.otlp.http.logs.OtlpHttpLogRecordExporter
import io.opentelemetry.exporter.otlp.http.trace.OtlpHttpSpanExporter
import io.opentelemetry.sdk.logs.SdkLoggerProvider
import io.opentelemetry.sdk.logs.export.SimpleLogRecordProcessor
import io.opentelemetry.sdk.resources.Resource
import io.opentelemetry.sdk.trace.SdkTracerProvider
import io.opentelemetry.sdk.trace.export.SimpleSpanProcessor

import java.io.PrintWriter
import java.io.StringWriter
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/**
 * Boomi-facing OpenTelemetry helper: full process/subprocess tracing plus
 * critical-failure telemetry to SigNoz. This class knows nothing about
 * MongoDB or the audit log contract -- it is a standalone building block
 * that any Boomi Groovy component can use for:
 *
 *  1. {@link #startSpan}/{@link #endSpan}/{@link #withSpan} -- start a
 *     timed span for the whole Boomi process, or for a lengthy subprocess
 *     within it, so SigNoz can show exactly how long each part took (a
 *     trace waterfall), and so a trace can be continued across separate
 *     Boomi shape executions via a portable traceparent string.
 *  2. {@link #currentTraceId()} -- reuse the trace ID of whatever
 *     OpenTelemetry span is currently active (if any), so multiple systems
 *     participating in one logical operation show up correlated in SigNoz.
 *  3. {@link #emitCriticalFailure} / {@link #recordError} -- send a
 *     critical, sanitized failure event to SigNoz via the real
 *     OpenTelemetry Logs SDK (not a hand-built OTLP payload), and record
 *     the same exception on a span so it is visible on the trace too.
 *
 * {@link BoomiAuditLogLibrary} (the MongoDB audit writer) is the first
 * caller of this class, but it is intentionally not the only one this class
 * knows about -- any other Boomi Groovy script that wants correlated
 * tracing or SigNoz failure telemetry can call it too, without pulling in
 * the MongoDB driver or the audit-log contract at all.
 *
 * See docs/references/boomi-groovy-library-architecture.md for the design
 * rationale (why this is a separate class from the Mongo writer) and the
 * tracing model in detail, and
 * docs/guides/boomi-audit-log-owner-guide.md for a plain-language
 * walkthrough aimed at Boomi process owners.
 */
class BoomiOtelLibrary {

  // Default SigNoz OTLP logs endpoint; overridable via BOOMI_AUDIT_OTEL_ENDPOINT.
  private static final String DEFAULT_OTEL_ENDPOINT =
    'http://otel-collector.signoz.svc.cluster.local:4318/v1/logs'

  // One OpenTelemetry Logs SDK logger per distinct (endpoint, service name)
  // pair, reused across calls -- avoids rebuilding an exporter/provider on
  // every failure.
  private static final Map<String, Logger> LOGGER_CACHE = new ConcurrentHashMap<>()
  private static volatile SdkLoggerProvider cachedLoggerProvider

  // One OpenTelemetry Tracer SDK tracer per distinct (endpoint, service
  // name) pair, reused the same way as LOGGER_CACHE above.
  private static final Map<String, Tracer> TRACER_CACHE = new ConcurrentHashMap<>()
  private static volatile SdkTracerProvider cachedTracerProvider

  // W3C traceparent propagation -- the standard, portable text format for
  // carrying a trace/span ID across a process boundary (for example a
  // Boomi Dynamic Process Property passed from one shape to a later one).
  private static final TextMapPropagator PROPAGATOR = W3CTraceContextPropagator.getInstance()

  private static final TextMapSetter<Map<String, String>> CARRIER_SETTER = new TextMapSetter<Map<String, String>>() {
    @Override
    void set(Map<String, String> carrier, String key, String value) {
      carrier?.put(key, value)
    }
  }

  private static final TextMapGetter<Map<String, String>> CARRIER_GETTER = new TextMapGetter<Map<String, String>>() {
    @Override
    Iterable<String> keys(Map<String, String> carrier) {
      return carrier?.keySet() ?: []
    }

    @Override
    String get(Map<String, String> carrier, String key) {
      return carrier?.get(key)
    }
  }

  /**
   * Resolves the OTLP/HTTP logs endpoint this library sends telemetry to.
   * Defaults to the in-cluster SigNoz collector; override with the
   * BOOMI_AUDIT_OTEL_ENDPOINT environment variable for local/dev use (for
   * example port-forwarded SigNoz on http://127.0.0.1:4318/v1/logs).
   */
  static String resolveEndpoint() {
    return System.getenv('BOOMI_AUDIT_OTEL_ENDPOINT') ?: DEFAULT_OTEL_ENDPOINT
  }

  /**
   * Resolves the OTLP/HTTP traces endpoint this library sends spans to.
   * Override with BOOMI_AUDIT_OTEL_TRACES_ENDPOINT; otherwise derived
   * automatically from resolveEndpoint() by swapping /v1/logs for
   * /v1/traces, so existing deployments that only set
   * BOOMI_AUDIT_OTEL_ENDPOINT need no changes to start getting traces too.
   */
  static String resolveTracesEndpoint() {
    String explicit = System.getenv('BOOMI_AUDIT_OTEL_TRACES_ENDPOINT')
    if (explicit) {
      return explicit
    }
    String logsEndpoint = resolveEndpoint()
    return logsEndpoint.contains('/v1/logs') ? logsEndpoint.replace('/v1/logs', '/v1/traces') : logsEndpoint
  }

  /**
   * Returns the trace ID of the currently active OpenTelemetry span, or
   * `null` when there is no valid active span. This is best-effort and
   * never throws -- a caller should fall back to generating its own
   * correlation ID (for example a UUID) when this returns `null`.
   */
  static String currentTraceId() {
    try {
      Span current = Span.current()
      SpanContext ctx = current?.spanContext
      if (ctx != null && ctx.isValid()) {
        return ctx.traceId
      }
    } catch (Exception ignored) {
      // OpenTelemetry context propagation is best-effort; never fail the
      // caller's real work because context extraction failed.
    }
    return null
  }

  /**
   * Emits a critical, sanitized failure log record to SigNoz via the
   * OpenTelemetry Logs SDK, and records the same exception on the
   * currently active span (if any) via `Span.recordException`, so the
   * failure is visible both as a standalone log entry and inline on the
   * trace. This method is best-effort and never throws -- any internal
   * telemetry problem (for example the collector being unreachable) is
   * swallowed here so it can never mask or replace the real failure the
   * caller is already handling.
   *
   * @param serviceName the OTel `service.name` resource attribute to tag
   *   this telemetry with (identifies which component is reporting)
   * @param failureType a short, machine-friendly category, for example
   *   `"validation"`, `"configuration"`, or `"mongo_write"`
   * @param message a sanitized, human-readable summary of the failure
   * @param traceId the correlation ID for this failure, if known (usually
   *   the same `trace_id` the caller put on its own record)
   * @param cause the underlying exception, if any -- its type, message, and
   *   stack trace are attached as log attributes (OTel exception semantic
   *   conventions) and it is recorded on the active span
   */
  static void emitCriticalFailure(String serviceName, String failureType, String message, String traceId, Throwable cause = null) {
    try {
      Logger otelLogger = getOrCreateLogger(resolveEndpoint(), serviceName ?: 'unknown-service')

      AttributesBuilder attrs = Attributes.builder()
        .put('failure.type', failureType ?: '')
        .put('failure.message', message ?: '')
        .put('trace_id', traceId ?: '')

      if (cause != null) {
        attrs.put('exception.type', cause.getClass().name)
        attrs.put('exception.message', cause.message ?: '')
        attrs.put('exception.stacktrace', stackTraceToString(cause))
      }

      otelLogger.logRecordBuilder()
        .setSeverity(Severity.ERROR)
        .setSeverityText('ERROR')
        .setBody("${serviceName} failure: ${failureType}" as String)
        .setAllAttributes(attrs.build())
        .emit()

      Span currentSpan = Span.current()
      if (cause != null && currentSpan?.spanContext?.isValid()) {
        currentSpan.recordException(cause)
      }
    } catch (Exception ignored) {
      // Telemetry is best-effort -- it must never prevent the caller's real
      // exception from propagating.
    }
  }

  /**
   * Emit structured telemetry log using the UNIFIED SCHEMA (same 10 base
   * fields as MongoDB audit logs). Use this for operational telemetry that
   * should preserve full business context for disaster recovery.
   *
   * Unified schema fields (all mandatory, use null/empty string if N/A):
   * - trace_id, ip, action, error_code, resource_type, resource_id, user_id
   * - message, tpl_message (both optional), meta
   *
   * @param traceId Correlation ID (same as MongoDB audit)
   * @param ip Source IP (null if N/A)
   * @param action Action being performed (e.g., "boomi.document.load", "config.fallback")
   * @param errorCode Error category (null if success, e.g., "BOM-OD-0001", "MONGO_TIMEOUT")
   * @param resourceType Type of resource (e.g., "boomi.document", "config.secret")
   * @param resourceId Specific resource ID (null if N/A)
   * @param userId User performing action (null if automated)
   * @param message Plain text message (null if using tpl_message)
   * @param tplMessage i18n template: [key: "...", params: [...]] (null if using message)
   * @param meta Structured metadata (Map)
   * @param severity Log severity (ERROR | WARN | INFO | DEBUG)
   * @param cause Optional exception (for exception.* fields)
   */
  static void emitTelemetry(
      String traceId,
      String ip,
      String action,
      String errorCode,
      String resourceType,
      String resourceId,
      String userId,
      String message,
      Map<String, Object> tplMessage,
      Map<String, Object> meta,
      String severity = 'INFO',
      Throwable cause = null
  ) {
    try {
      Logger otelLogger = getOrCreateLogger(resolveEndpoint(), 'oms-telemetry')

      AttributesBuilder attrs = Attributes.builder()
        // Core unified fields (same as MongoDB audit)
        .put('trace_id', traceId ?: '')
        .put('ip', ip ?: '')
        .put('action', action ?: '')
        .put('error_code', errorCode ?: '')  // null becomes empty string
        .put('resource_type', resourceType ?: '')
        .put('resource_id', resourceId ?: '')
        .put('user_id', userId ?: '')

      // message is optional (use null if not provided)
      if (message != null) {
        attrs.put('message', message)
      }

      // tpl_message is optional structured template
      if (tplMessage != null && tplMessage['key']) {
        attrs.put('tpl_message.key', tplMessage['key'] as String)
        if (tplMessage['params'] instanceof Map) {
          ((Map) tplMessage['params']).each { k, v ->
            attrs.put("tpl_message.params.${k}" as String, v?.toString() ?: '')
          }
        }
      }

      // meta fields (flatten Map into attributes)
      if (meta != null) {
        meta.each { k, v ->
          attrs.put("meta.${k}" as String, v?.toString() ?: '')
        }
      }

      // Exception details (SigNoz-specific)
      if (cause != null) {
        attrs.put('exception.type', cause.getClass().name)
        attrs.put('exception.message', cause.message ?: '')
        attrs.put('exception.stacktrace', stackTraceToString(cause))
      }

      // Emit log
      Severity otelSeverity = parseSeverity(severity)
      otelLogger.logRecordBuilder()
        .setSeverity(otelSeverity)
        .setSeverityText(severity)
        .setBody(message ?: (tplMessage?['key'] as String) ?: '')
        .setAllAttributes(attrs.build())
        .emit()

      // Record exception on active span if present
      Span currentSpan = Span.current()
      if (cause != null && currentSpan?.spanContext?.isValid()) {
        currentSpan.recordException(cause)
      }
    } catch (Exception ignored) {
      // Telemetry is best-effort
    }
  }

  /**
   * Convenience wrapper: emit critical failure with full business context.
   * Use when MongoDB write fails or business operation fails — full audit
   * context preserved for disaster recovery.
   */
  static void emitCriticalFailureWithContext(
      String traceId,
      String ip,
      String action,
      String errorCode,
      String resourceType,
      String resourceId,
      String userId,
      String message,
      Map<String, Object> tplMessage,
      Map<String, Object> meta,
      Throwable cause = null
  ) {
    emitTelemetry(
      traceId, ip, action, errorCode, resourceType, resourceId, userId,
      message, tplMessage, meta, 'ERROR', cause
    )
  }

  /**
   * Convenience wrapper: emit warning (config fallback, retry, etc.)
   */
  static void emitWarning(
      String traceId,
      String action,
      String errorCode,
      String resourceType,
      String resourceId,
      String message,
      Map<String, Object> meta
  ) {
    emitTelemetry(
      traceId, null, action, errorCode, resourceType, resourceId, null,
      message, null, meta, 'WARN', null
    )
  }

  /**
   * Convenience wrapper: emit success (audit write succeeded, etc.)
   */
  static void emitSuccess(
      String traceId,
      String action,
      String resourceType,
      String resourceId,
      String message,
      Map<String, Object> meta
  ) {
    emitTelemetry(
      traceId, null, action, null, resourceType, resourceId, null,
      message, null, meta, 'INFO', null
    )
  }

  /**
   * Parse severity string to OpenTelemetry Severity enum
   */
  private static Severity parseSeverity(String severity) {
    switch (severity?.toUpperCase()) {
      case 'ERROR': return Severity.ERROR
      case 'WARN': return Severity.WARN
      case 'INFO': return Severity.INFO
      case 'DEBUG': return Severity.DEBUG
      default: return Severity.INFO
    }
  }

  /**
   * Closes and clears the cached OpenTelemetry logger/tracer provider(s).
   * Call this from short-lived batch jobs or tests that need a clean
   * shutdown; not required for long-running Boomi runtimes, which should
   * keep reusing the cached providers.
   */
  static void shutdown() {
    LOGGER_CACHE.clear()
    TRACER_CACHE.clear()
    if (cachedLoggerProvider != null) {
      cachedLoggerProvider.shutdown()
      cachedLoggerProvider = null
    }
    if (cachedTracerProvider != null) {
      cachedTracerProvider.shutdown()
      cachedTracerProvider = null
    }
  }

  // ---------------------------------------------------------------------
  // Span lifecycle -- process- and subprocess-level tracing
  // ---------------------------------------------------------------------

  /**
   * Starts a new span (a timed unit of work, shown as one bar on a SigNoz
   * trace waterfall) named `spanName`, tagged with `serviceName`. Use this
   * to mark the start of the whole Boomi process, or of a lengthy
   * subprocess within it, so SigNoz can show exactly how long each part
   * took and which one is slow.
   *
   * Nesting works two ways:
   *  - Same script execution: call startSpan again before ending the outer
   *    one, and the new span automatically becomes a child of it (no extra
   *    work needed) -- this is the common case for "lengthy subprocess
   *    within one process run."
   *  - Separate Boomi shape/script execution: pass the traceparent string
   *    from the earlier span's handle (see below) as parentTraceparent,
   *    typically read back from a Boomi Dynamic Process Property. This
   *    makes the new span a child of that one even though the original
   *    span's in-memory object no longer exists in this execution.
   * Omit parentTraceparent with nothing else active to start a brand-new
   * trace (for example the very first span of the whole Boomi process).
   *
   * @return a span handle Map you must later pass to {@link #endSpan}:
   *   [span, scope, traceparent, traceId, spanId]. Store traceparent (a
   *   plain String) in a Boomi Dynamic Process Property if a later,
   *   separate shape execution needs to continue this same trace.
   */
  static Map startSpan(String serviceName, String spanName, String parentTraceparent = null) {
    Tracer tracer = getOrCreateTracer(serviceName ?: 'unknown-service')
    def builder = tracer.spanBuilder(spanName)
    if (parentTraceparent) {
      builder.setParent(extractContext(parentTraceparent))
    }
    // If parentTraceparent is not supplied, the builder inherits whatever
    // span is already ambiently "current" in this thread (an enclosing
    // startSpan's scope), or starts a new root trace if none is active.
    Span span = builder.startSpan()
    Scope scope = span.makeCurrent()
    String traceparent = injectTraceparent(span)
    return [
      span: span,
      scope: scope,
      traceparent: traceparent,
      traceId: span.spanContext.traceId,
      spanId: span.spanContext.spanId
    ]
  }

  /**
   * Ends a span started by {@link #startSpan}, recording its end time.
   * Always call this exactly once per startSpan call -- prefer
   * {@link #withSpan} where possible, since it guarantees this even when
   * the work inside throws.
   *
   * @param spanHandle the Map returned by {@link #startSpan}
   * @param error when supplied, the span is marked as failed (OTel
   *   StatusCode.ERROR), the exception is recorded on it, and a critical
   *   failure log is also emitted to SigNoz via {@link #emitCriticalFailure}
   *   -- you do not need to call that yourself in this case.
   */
  static void endSpan(Map spanHandle, Throwable error = null) {
    if (spanHandle == null) {
      return
    }
    Span span = spanHandle.span as Span
    try {
      if (span != null) {
        if (error != null) {
          span.recordException(error)
          span.setStatus(StatusCode.ERROR, error.message ?: error.getClass().simpleName)
        }
        span.end()
      }
    } catch (Exception ignored) {
      // Telemetry is best-effort -- never let a span-ending problem mask
      // the caller's real work.
    } finally {
      try {
        (spanHandle.scope as Scope)?.close()
      } catch (Exception ignored) {
        // best-effort
      }
    }
    if (error != null) {
      emitCriticalFailure('boomi-process', 'span_error', error.message, spanHandle.traceId as String, error)
    }
  }

  /**
   * Convenience wrapper around {@link #startSpan}/{@link #endSpan} for the
   * common "time this block of work" case, guaranteeing the span is always
   * ended -- including when work throws, in which case the span is marked
   * as failed and the exception is re-thrown unchanged. Prefer this over
   * calling startSpan/endSpan manually whenever the subprocess is fully
   * contained in one script execution.
   *
   * Example:
   *   BoomiOtelLibrary.withSpan('oms-audit-writer', 'boomi.process.load_file') { handle ->
   *     // ... lengthy subprocess work ...
   *   }
   *
   * @return whatever work returns
   */
  static Object withSpan(String serviceName, String spanName, String parentTraceparent = null, Closure work) {
    Map handle = startSpan(serviceName, spanName, parentTraceparent)
    try {
      Object result = work.call(handle)
      endSpan(handle)
      return result
    } catch (Throwable t) {
      endSpan(handle, t)
      throw t
    }
  }

  /**
   * Records an error against a span without ending it -- for example a
   * recoverable problem partway through a lengthy subprocess that will
   * still run to completion and be ended normally. Always also emits a
   * critical failure log to SigNoz via {@link #emitCriticalFailure}. If
   * spanHandle is null, only the SigNoz log is emitted (there is no span
   * to attach the exception to).
   */
  static void recordError(String serviceName, Map spanHandle, String message, Throwable cause) {
    try {
      Span span = spanHandle?.span as Span
      if (span != null && cause != null) {
        span.recordException(cause)
        span.setStatus(StatusCode.ERROR, message ?: cause.message ?: '')
      }
    } catch (Exception ignored) {
      // best-effort
    }
    String traceId = (spanHandle?.traceId as String) ?: currentTraceId()
    emitCriticalFailure(serviceName, 'process_error', message, traceId, cause)
  }

  private static Tracer getOrCreateTracer(String serviceName) {
    String endpoint = resolveTracesEndpoint()
    String cacheKey = "${endpoint}|${serviceName}"
    return TRACER_CACHE.computeIfAbsent(cacheKey, { String ignoredKey ->
      OtlpHttpSpanExporter exporter = OtlpHttpSpanExporter.builder()
        .setEndpoint(endpoint)
        .setTimeout(2, TimeUnit.SECONDS)
        .build()
      SdkTracerProvider provider = SdkTracerProvider.builder()
        .setResource(
          Resource.getDefault().toBuilder()
            .put('service.name', serviceName)
            .build()
        )
        .addSpanProcessor(SimpleSpanProcessor.create(exporter))
        .build()
      cachedTracerProvider = provider
      return provider.get('boomi.BoomiOtelLibrary')
    })
  }

  /**
   * Encodes a span's context as a W3C traceparent string -- the portable
   * format for carrying a trace across a process boundary (for example a
   * Boomi Dynamic Process Property).
   */
  private static String injectTraceparent(Span span) {
    Map<String, String> carrier = [:]
    Context ctx = Context.root().with(span)
    PROPAGATOR.inject(ctx, carrier, CARRIER_SETTER)
    return carrier['traceparent']
  }

  /**
   * Decodes a W3C traceparent string (as produced by
   * {@link #injectTraceparent}) back into an OpenTelemetry Context usable
   * as a new span's parent.
   */
  private static Context extractContext(String traceparent) {
    if (!traceparent) {
      return Context.root()
    }
    Map<String, String> carrier = [traceparent: traceparent]
    return PROPAGATOR.extract(Context.root(), carrier, CARRIER_GETTER)
  }

  private static Logger getOrCreateLogger(String endpoint, String serviceName) {
    String cacheKey = "${endpoint}|${serviceName}"
    return LOGGER_CACHE.computeIfAbsent(cacheKey, { String ignoredKey ->
      OtlpHttpLogRecordExporter exporter = OtlpHttpLogRecordExporter.builder()
        .setEndpoint(endpoint)
        .setTimeout(2, TimeUnit.SECONDS)
        .build()
      SdkLoggerProvider provider = SdkLoggerProvider.builder()
        .setResource(
          Resource.getDefault().toBuilder()
            .put('service.name', serviceName)
            .build()
        )
        .addLogRecordProcessor(SimpleLogRecordProcessor.create(exporter))
        .build()
      cachedLoggerProvider = provider
      return provider.get('boomi.BoomiOtelLibrary')
    })
  }

  /**
   * Renders a Throwable's stack trace as a String for inclusion in a log
   * record attribute (OTel exception semantic conventions).
   */
  private static String stackTraceToString(Throwable t) {
    StringWriter sw = new StringWriter()
    t.printStackTrace(new PrintWriter(sw))
    return sw.toString()
  }
}
