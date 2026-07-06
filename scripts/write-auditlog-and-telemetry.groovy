#!/usr/bin/env groovy

// Test harness for the Boomi audit-log library.

import groovy.cli.commons.CliBuilder
import groovy.json.JsonOutput

import boomi.BoomiAuditLogLibrary

import java.time.Instant
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

cli._(longOpt: 'db', args: 1, argName: 'name', 'MongoDB database name (default: test_db)')
cli._(longOpt: 'collection', args: 1, argName: 'name', 'MongoDB collection name (default: auditlogs)')
cli._(longOpt: 'otel-endpoint', args: 1, argName: 'url', 'OTLP logs endpoint (default: http://127.0.0.1:3301/v1/logs)')
cli._(longOpt: 'service-name', args: 1, argName: 'name', 'Service name for telemetry (default: oms-audit-simulator)')

cli._(longOpt: 'resource-id', args: 1, argName: 'id', 'Audit resource id (default: ORD-2024-001)')
cli._(longOpt: 'user-id', args: 1, argName: 'id', 'Audit user id (default: user1)')

def options = cli.parse(args)
if (!options || options.h) {
  cli.usage()
  System.exit(0)
}

String dbName = options.'db' ?: 'oms_audit'
String collectionName = options.'collection' ?: 'auditlogs'
String otelEndpoint = options.'otel-endpoint' ?: 'http://127.0.0.1:3301/v1/logs'
String serviceName = options.'service-name' ?: 'oms-audit-simulator'
String resourceId = options.'resource-id' ?: 'ORD-2024-001'
String userId = options.'user-id' ?: 'user1'

String traceId = UUID.randomUUID().toString().replace('-', '')
Instant now = Instant.now().truncatedTo(ChronoUnit.SECONDS)
String nowIso = now.toString()
String nowNano = String.valueOf(now.toEpochMilli() * 1_000_000L)

String mongoUri = BoomiAuditLogLibrary.resolveMongoUri([
  mongoUri: options.'mongo-uri',
  k8sSecretName: options.'mongo-uri-k8s-secret',
  k8sNamespace: options.'mongo-uri-k8s-namespace',
  k8sSecretKey: options.'mongo-uri-k8s-key',
  awsSecretId: options.'mongo-uri-secret-id',
  awsRegion: options.'aws-region'
])

Map<String, Object> record = [
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
    key: 'orders.order.status.changed',
    params: [
      order_no: resourceId,
      from: 'PENDING',
      to: 'PROCESSING'
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
]

println 'Writing sample audit log to MongoDB...'
def mongoResult = BoomiAuditLogLibrary.writeAuditLog(mongoUri, dbName, collectionName, record)
println JsonOutput.prettyPrint(JsonOutput.toJson([
  insertedId: mongoResult.insertedId,
  traceId: traceId,
  action: record.action,
  time: nowIso,
  db: dbName,
  collection: collectionName,
  savedDocument: mongoResult.savedDocument
]))

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
        body: [stringValue: 'orders.order.confirm'],
        attributes: [
          [key: 'trace_id', value: [stringValue: traceId]],
          [key: 'action', value: [stringValue: 'orders.order.confirm']],
          [key: 'resource_type', value: [stringValue: 'orders.order']],
          [key: 'resource_id', value: [stringValue: resourceId]],
          [key: 'user_id', value: [stringValue: userId]],
          [key: 'http.method', value: [stringValue: 'POST']],
          [key: 'http.path', value: [stringValue: "/api/v1/orders/${resourceId}/confirm"]],
          [key: 'http.status_code', value: [intValue: '200']],
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
println "Done. Trace ID: ${traceId}"

// Cleanup test data after successful run
println 'Cleaning up test record from MongoDB...'
def cleanupClient = com.mongodb.client.MongoClients.create(mongoUri)
try {
  def cleanupDb = cleanupClient.getDatabase(dbName)
  def cleanupCol = cleanupDb.getCollection(collectionName)
  def deleteResult = cleanupCol.deleteOne(new org.bson.Document('trace_id', traceId))
  if (deleteResult.deletedCount > 0) {
    println "Cleanup: removed test record (trace_id: ${traceId})"
  } else {
    println "Cleanup: record not found (may have been already removed)"
  }
} finally {
  cleanupClient.close()
}

println 'Test complete — no test data left in database.'
