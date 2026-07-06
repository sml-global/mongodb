package boomi

@Grab('org.mongodb:mongodb-driver-sync:5.1.2')
@Grab('software.amazon.awssdk:secretsmanager:2.25.48')

import com.mongodb.client.MongoClients
import org.bson.Document

import software.amazon.awssdk.core.SdkBytes
import software.amazon.awssdk.regions.Region
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest

import groovy.json.JsonSlurper

import java.util.Base64

class BoomiAuditLogLibrary {
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
      def candidate = parsed.mongoUri ?: parsed.mongodbUri ?: parsed.uri ?: parsed.MONGO_URI
      if (!candidate) {
        throw new RuntimeException('Secret JSON does not contain mongoUri/mongodbUri/uri/MONGO_URI key')
      }
      return candidate.toString()
    }

    return trimmed
  }

  static String resolveMongoUri(Map options = [:]) {
    if (options.mongoUri) {
      return options.mongoUri.toString()
    }

    if (options.k8sSecretName) {
      String namespace = (options.k8sNamespace ?: 'mongodb').toString()
      String key = (options.k8sSecretKey ?: 'mongoUri').toString()
      return readKubernetesSecretValue(namespace, options.k8sSecretName.toString(), key)
    }

    if (options.awsSecretId) {
      String region = (options.awsRegion ?: System.getenv('AWS_REGION') ?: 'ap-east-1').toString()
      String payload = readAwsSecretString(options.awsSecretId.toString(), region)
      return extractMongoUriFromSecretPayload(payload)
    }

    return 'mongodb://127.0.0.1:27017/?directConnection=true'
  }

  static Map<String, Object> writeAuditLog(String mongoUri, String dbName, String collectionName, Map<String, Object> record) {
    def client = MongoClients.create(mongoUri)
    try {
      def database = client.getDatabase(dbName)
      def collection = database.getCollection(collectionName)

      def insertResult = collection.insertOne(new Document(record))
      def insertedId = insertResult.getInsertedId()
      def savedDoc = collection.find(new Document('_id', insertedId)).first()

      return [
        insertedId: insertedId?.asObjectId()?.value?.toHexString(),
        savedDocument: savedDoc
      ]
    } finally {
      client.close()
    }
  }
}
