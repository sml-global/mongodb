#!/usr/bin/env groovy

// Test harness for the Boomi audit-log library.

@Grab('org.apache.poi:poi-ooxml:5.2.5')

import groovy.cli.commons.CliBuilder
import groovy.json.JsonOutput
import org.apache.poi.ss.usermodel.CellType
import org.apache.poi.ss.usermodel.DataFormatter
import org.apache.poi.ss.usermodel.Row
import org.apache.poi.ss.usermodel.Sheet
import org.apache.poi.xssf.usermodel.XSSFWorkbook

import boomi.BoomiAuditLogLibrary

import java.time.LocalDateTime
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.UUID

CliBuilder cli = new CliBuilder(
  usage: 'write-auditlog-and-telemetry.groovy [options]',
  header: 'Test harness: write audit log to MongoDB and send matching OTLP log telemetry.'
)
cli.h(longOpt: 'help', 'Show help')

cli._(longOpt: 'mongo-uri', args: 1, argName: 'uri', 'MongoDB URI')
cli._(longOpt: 'mongo-uri-k8s-secret', args: 1, argName: 'name', 'Kubernetes secret name that stores MongoDB URI')
cli._(longOpt: 'mongo-uri-k8s-namespace', args: 1, argName: 'name', 'Kubernetes secret namespace (default: mongodb)')
cli._(longOpt: 'mongo-uri-k8s-key', args: 1, argName: 'key', 'Kubernetes secret key (default: mongoUri)')
cli._(longOpt: 'mongo-uri-secret-id', args: 1, argName: 'id', 'AWS Secrets Manager secret ID containing MongoDB URI')
cli._(longOpt: 'aws-region', args: 1, argName: 'region', 'AWS region for Secrets Manager lookup')

cli._(longOpt: 'db', args: 1, argName: 'name', 'MongoDB database name (default: oms_audit)')
cli._(longOpt: 'collection', args: 1, argName: 'name', 'MongoDB collection name (default: auditlogs)')
cli._(longOpt: 'otel-endpoint', args: 1, argName: 'url', 'OTLP logs endpoint (default: http://127.0.0.1:3301/v1/logs)')
cli._(longOpt: 'service-name', args: 1, argName: 'name', 'Service name for telemetry (default: oms-audit-simulator)')

cli._(longOpt: 'resource-id', args: 1, argName: 'id', 'Audit resource id (default: ORD-2024-001)')
cli._(longOpt: 'user-id', args: 1, argName: 'id', 'Audit user id (default: user1)')
cli._(longOpt: 'boomi-log-xlsx', args: 1, argName: 'path', 'Path to Boomi log workbook (default: logs/EDI Loader Logging.xlsx)')

def options = cli.parse(args)
if (!options || options.h) {
  cli.usage()
  System.exit(0)
}

String dbName = 'oms_audit'
String collectionName = 'auditlogs'
String otelEndpoint = options.'otel-endpoint' ?: 'http://127.0.0.1:3301/v1/logs'
String serviceName = options.'service-name' ?: 'oms-audit-simulator'
String resourceId = options.'resource-id' ?: 'ORD-2024-001'
String userId = options.'user-id' ?: 'user1'
String boomiLogXlsx = options.'boomi-log-xlsx' ?: 'logs/EDI Loader Logging.xlsx'

String traceId = UUID.randomUUID().toString().replace('-', '')
Instant now = Instant.now().truncatedTo(ChronoUnit.SECONDS)
String nowIso = now.toString()
String nowNano = String.valueOf(now.toEpochMilli() * 1_000_000L)

String cellString(Row row, Integer idx, DataFormatter formatter) {
  if (idx == null || idx < 0) {
    return ''
  }
  def cell = row.getCell(idx, Row.MissingCellPolicy.RETURN_BLANK_AS_NULL)
  if (cell == null) {
    return ''
  }
  if (cell.getCellType() == CellType.NUMERIC && org.apache.poi.ss.usermodel.DateUtil.isCellDateFormatted(cell)) {
    LocalDateTime local = cell.getLocalDateTimeCellValue()
    return local.toString().replace('T', ' ')
  }
  return formatter.formatCellValue(cell)?.trim() ?: ''
}

String normalizeTimestamp(String rawTs, String fallbackIso) {
  if (!rawTs?.trim()) {
    return fallbackIso
  }

  List<String> patterns = [
    'yyyy-MM-dd HH:mm:ss',
    'yyyy-MM-dd\'T\'HH:mm:ss'
  ]

  for (String pattern : patterns) {
    try {
      LocalDateTime parsed = LocalDateTime.parse(rawTs.trim(), DateTimeFormatter.ofPattern(pattern))
      return parsed.atOffset(ZoneOffset.UTC).toInstant().truncatedTo(ChronoUnit.SECONDS).toString()
    } catch (Exception ignored) {
      // Try next timestamp format.
    }
  }

  try {
    return Instant.parse(rawTs.trim()).truncatedTo(ChronoUnit.SECONDS).toString()
  } catch (Exception ignored) {
    return fallbackIso
  }
}

String extractIp(String serverName) {
  if (!serverName) {
    return '0.0.0.0'
  }
  def matcher = (serverName =~ /(\d{1,3}(?:\.\d{1,3}){3})/)
  return matcher.find() ? matcher.group(1) : '0.0.0.0'
}

Map<String, Object> mapBoomiRowToAuditRecord(Map<String, String> raw, String sheetName, String fallbackTimeIso, String fallbackResourceId, String fallbackUserId) {
  boolean isError = sheetName.equalsIgnoreCase('Error')

  String source = raw['Source'] ?: 'boomi'
  String event = raw['Event'] ?: (isError ? 'On Error' : 'Track')
  String processId = raw['ProcessID'] ?: ''
  String rowId = raw['ID'] ?: ''
  String resourceIdValue = processId ?: rowId ?: fallbackResourceId
  String serverName = raw['Server Name'] ?: fallbackUserId
  String startTime = normalizeTimestamp(raw['StartTime'] ?: '', fallbackTimeIso)
  String messageLog = raw['MessageLog'] ?: ''

  return [
    trace_id: UUID.randomUUID().toString().replace('-', ''),
    ip: extractIp(serverName),
    time: startTime,
    // Contract naming: the verb never encodes the outcome. A Track row is an
    // informational milestone (flag verb, error_code null); an Error row is
    // the process run completing with a failure (complete verb + error_code).
    action: isError ? 'boomi.process.complete' : 'boomi.process.flag',
    error_code: isError ? 'BOM-OD-0001' : null,
    resource_type: 'boomi.process',
    resource_id: resourceIdValue,
    user_id: source ?: fallbackUserId,
    message: isError ? messageLog : null,
    tpl_message: [
      key: isError ? 'boomi.process.error.logged' : 'boomi.process.track.logged',
      params: [
        source_system: 'boomi',
        sheet: sheetName,
        event: event,
        source: source,
        source_info: raw['SourceInfo'] ?: '',
        process_id: processId,
        event_id: rowId,
        server_name: serverName,
        start_time: raw['StartTime'] ?: '',
        original_message_log: messageLog,
        message_log: messageLog,
        notify: raw['Notify'] ?: '',
        fileconfig_id: raw['fk_fileconfig_fileconfigid'] ?: ''
      ]
    ],
    // No before/after field diff exists for an EDI tracking row, so no
    // resource_changes -- per the contract, leave it null rather than
    // inventing a fake old/new pair.
    resource_changes: null,
    meta: [
      method: 'BOOMI',
      path: source,
      status: isError ? 500 : 200,
      ua: serverName,
      sheet: sheetName,
      source_system: 'boomi'
    ]
  ]
}

List<Map<String, Object>> loadBoomiAuditRecordsFromWorkbook(String workbookPath, String fallbackTimeIso, String fallbackResourceId, String fallbackUserId) {
  File workbookFile = new File(workbookPath)
  if (!workbookFile.exists()) {
    return []
  }

  DataFormatter formatter = new DataFormatter()
  List<Map<String, Object>> records = []

  workbookFile.withInputStream { input ->
    XSSFWorkbook workbook = new XSSFWorkbook(input)
    try {
      ['Normal', 'Error'].each { String sheetName ->
        Sheet sheet = workbook.getSheet(sheetName)
        if (sheet == null) {
          return
        }

        Row header = sheet.getRow(sheet.getFirstRowNum())
        if (header == null) {
          return
        }

        Map<String, Integer> headerIndex = [:]
        header.cellIterator().each { cell ->
          String key = formatter.formatCellValue(cell)?.trim()
          if (key) {
            headerIndex[key] = cell.columnIndex
          }
        }

        int start = sheet.getFirstRowNum() + 1
        int end = sheet.getLastRowNum()
        for (int i = start; i <= end; i++) {
          Row row = sheet.getRow(i)
          if (row == null) {
            continue
          }

          Map<String, String> raw = [:]
          headerIndex.each { String key, Integer idx ->
            raw[key] = cellString(row, idx, formatter)
          }

          if ((raw['ID'] ?: '').isEmpty() && (raw['ProcessID'] ?: '').isEmpty() && (raw['MessageLog'] ?: '').isEmpty()) {
            continue
          }

          records << mapBoomiRowToAuditRecord(raw, sheetName, fallbackTimeIso, fallbackResourceId, fallbackUserId)
        }
      }
    } finally {
      workbook.close()
    }
  }

  return records
}

// BoomiAuditLogLibrary.writeAuditLog() resolves the MongoDB URI, database,
// and collection internally. These CLI flags are translated into the same
// override properties the library checks, so the existing flags keep working
// without the caller needing to pass a URI/db/collection through by hand.
if (options.'mongo-uri') {
  System.setProperty('BOOMI_AUDIT_MONGO_URI', options.'mongo-uri')
}
if (options.'mongo-uri-k8s-secret') {
  System.setProperty('BOOMI_AUDIT_K8S_SECRET_NAME', options.'mongo-uri-k8s-secret')
}
if (options.'mongo-uri-k8s-namespace') {
  System.setProperty('BOOMI_AUDIT_K8S_NAMESPACE', options.'mongo-uri-k8s-namespace')
}
if (options.'mongo-uri-k8s-key') {
  System.setProperty('BOOMI_AUDIT_K8S_SECRET_KEY', options.'mongo-uri-k8s-key')
}
if (options.'mongo-uri-secret-id') {
  System.setProperty('BOOMI_AUDIT_AWS_SECRET_ID', options.'mongo-uri-secret-id')
}
if (options.'aws-region') {
  System.setProperty('AWS_REGION', options.'aws-region')
}

List<Map<String, Object>> records = loadBoomiAuditRecordsFromWorkbook(boomiLogXlsx, nowIso, resourceId, userId)
if (records.isEmpty()) {
  records = [[
    trace_id: traceId,
    ip: '192.168.1.122',
    time: nowIso,
    action: 'orders.order.confirm',
    error_code: null,
    resource_type: 'orders.order',
    resource_id: resourceId,
    user_id: userId,
    message: null,
    tpl_message: [
      key: 'orders.order.confirmed',
      params: [
        order_no: resourceId
      ]
    ],
    resource_changes: [
      status: ['pending', 'confirmed']
    ],
    meta: [
      method: 'POST',
      path: "/api/v1/orders/${resourceId}/confirm",
      status: 200,
      ua: 'Mozilla/5.0'
    ]
  ]]
}

println "Writing ${records.size()} audit log record(s) to MongoDB..."
List<Map<String, Object>> mongoResults = []
records.each { Map<String, Object> record ->
  def mongoResult = BoomiAuditLogLibrary.writeAuditLog(record)
  mongoResults << [
    insertedId: mongoResult.insertedId,
    traceId: mongoResult.trace_id,
    action: record.action,
    time: mongoResult.time,
    resourceId: record.resource_id
  ]
}

println JsonOutput.prettyPrint(JsonOutput.toJson([
  insertedCount: mongoResults.size(),
  db: dbName,
  collection: collectionName,
  sampleResults: mongoResults.take(5)
]))

Map<String, Object> telemetryRecord = records[0]
String telemetryTraceId = telemetryRecord.trace_id?.toString() ?: traceId
String telemetryAction = telemetryRecord.action?.toString() ?: 'boomi.process.flag'
String telemetryResourceType = telemetryRecord.resource_type?.toString() ?: 'boomi.process'
String telemetryResourceId = telemetryRecord.resource_id?.toString() ?: resourceId
String telemetryUserId = telemetryRecord.user_id?.toString() ?: userId
String telemetryPath = telemetryRecord.meta instanceof Map ? (telemetryRecord.meta.path?.toString() ?: '/boomi/process') : '/boomi/process'
String telemetryStatus = telemetryRecord.meta instanceof Map ? String.valueOf(telemetryRecord.meta.status ?: 200) : '200'

Map<String, Object> otelPayload = [
  resourceLogs: [[
    resource: [
      attributes: [
        [key: 'service.name', value: [stringValue: serviceName]],
        [key: 'deployment.environment', value: [stringValue: 'dev']]
      ]
    ],
    scopeLogs: [[
      scope: [name: 'oms.auditlog.writer', version: '2.0.0'],
      logRecords: [[
        timeUnixNano: nowNano,
        severityNumber: 9,
        severityText: 'INFO',
        body: [stringValue: telemetryAction],
        attributes: [
          [key: 'trace_id', value: [stringValue: telemetryTraceId]],
          [key: 'action', value: [stringValue: telemetryAction]],
          [key: 'resource_type', value: [stringValue: telemetryResourceType]],
          [key: 'resource_id', value: [stringValue: telemetryResourceId]],
          [key: 'user_id', value: [stringValue: telemetryUserId]],
          [key: 'http.method', value: [stringValue: 'BOOMI']],
          [key: 'http.path', value: [stringValue: telemetryPath]],
          [key: 'http.status_code', value: [intValue: telemetryStatus]],
          [key: 'records.inserted', value: [intValue: String.valueOf(records.size())]],
          [key: 'db.system', value: [stringValue: 'mongodb']],
          [key: 'db.name', value: [stringValue: dbName]],
          [key: 'db.collection', value: [stringValue: collectionName]]
        ]
      ]]
    ]]
  ]]
]

println 'Sending OTLP telemetry event to SigNoz...'
boolean sent = false
String payload = JsonOutput.toJson(otelPayload)
for (int attempt = 1; attempt <= 5; attempt++) {
  HttpURLConnection conn = (HttpURLConnection) new URL(otelEndpoint).openConnection()
  conn.setRequestMethod('POST')
  conn.setDoOutput(true)
  conn.setConnectTimeout(5000)
  conn.setReadTimeout(10000)
  conn.setRequestProperty('Content-Type', 'application/json')

  conn.outputStream.withWriter('UTF-8') { it << payload }

  int code = conn.responseCode
  if (code >= 200 && code < 300) {
    sent = true
    break
  }

  String err = conn.errorStream != null ? conn.errorStream.getText('UTF-8').trim() : ''
  System.err.println("Telemetry send attempt ${attempt}/5 failed: HTTP ${code} ${err}")
  sleep(2000)
}

if (!sent) {
  System.err.println("Error: failed to send telemetry to '${otelEndpoint}' after retries.")
  System.err.println('Hint: use ingress URL in production; for dev you can still use: kubectl -n signoz port-forward svc/signoz 3301:8080')
  System.exit(1)
}

println 'Telemetry sent successfully.'
println "Done. Inserted ${records.size()} record(s). Sample trace ID: ${telemetryTraceId}"
