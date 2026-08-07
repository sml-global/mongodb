package com.boomi.elt.s3

import com.amazonaws.auth.AWSStaticCredentialsProvider
import com.amazonaws.auth.BasicSessionCredentials
import com.amazonaws.auth.DefaultAWSCredentialsProviderChain
import com.amazonaws.services.s3.AmazonS3
import com.amazonaws.services.s3.AmazonS3ClientBuilder
import com.amazonaws.services.s3.model.ObjectListing
import com.amazonaws.services.s3.model.ObjectMetadata
import com.amazonaws.services.s3.model.PutObjectRequest
import com.amazonaws.services.s3.model.S3Object
import com.amazonaws.services.securitytoken.AWSSecurityTokenService
import com.amazonaws.services.securitytoken.AWSSecurityTokenServiceClientBuilder
import com.amazonaws.services.securitytoken.model.AssumeRoleRequest
import com.amazonaws.services.securitytoken.model.AssumeRoleResult
import com.amazonaws.services.securitytoken.model.Credentials

/**
 * Boomi ELT S3 Library - Cross-Account S3 Access
 *
 * Enables Boomi processes running in Production to read/write S3 buckets in
 * UAT, DEV, and SIT environments using AWS STS AssumeRole.
 *
 * Prerequisites:
 * - Production Boomi atom has IAM role: sml-elt-admin-prod
 * - Target accounts have assumable roles: sml-elt-cross-account-{env}
 * - Terraform provisioned via platform-prerequisites/terraform/boomi-elt-s3/
 *
 * Usage:
 *   def s3 = new BoomiEltS3Library()
 *
 *   // Read from UAT
 *   String content = s3.readObject("uat", "documents/order-001.csv")
 *
 *   // Write to DEV
 *   s3.writeObject("dev", "processed/order-001.csv", content)
 *
 *   // List files in SIT
 *   List<String> files = s3.listObjects("sit", "documents/")
 *
 * Author: Claude Code
 * Version: 1.0.0
 * Date: 2026-08-06
 */
class BoomiEltS3Library {

    private static final String REGION = "ap-east-1"

    // Account ID mapping (loaded from environment variables or Boomi properties)
    private static final Map<String, String> ACCOUNT_IDS = loadAccountIds()

    // External IDs for AssumeRole (security measure)
    private static final Map<String, String> EXTERNAL_IDS = [
        prod: null,
        uat: "boomi-elt-uat",
        dev: "boomi-elt-dev",
        sit: "boomi-elt-sit"
    ]

    // Bucket names
    private static final Map<String, String> BUCKET_NAMES = [
        prod: "sml-elt-prod",
        uat: "sml-elt-uat",
        dev: "sml-elt-dev",
        sit: "sml-elt-sit"
    ]

    /**
     * Load AWS account IDs from environment variables or Boomi dynamic process properties
     *
     * Environment variables (preferred):
     *   AWS_ACCOUNT_ID_PROD, AWS_ACCOUNT_ID_UAT, AWS_ACCOUNT_ID_DEV, AWS_ACCOUNT_ID_SIT
     *
     * Boomi Dynamic Process Properties (fallback):
     *   boomi.elt.account.prod, boomi.elt.account.uat, boomi.elt.account.dev, boomi.elt.account.sit
     *
     * @return Map of environment -> 12-digit account ID
     */
    private static Map<String, String> loadAccountIds() {
        def accountIds = [:]

        ['prod', 'uat', 'dev', 'sit'].each { env ->
            String envVar = System.getenv("AWS_ACCOUNT_ID_${env.toUpperCase()}")
            String propKey = "boomi.elt.account.${env}"

            // Try environment variable first, then Boomi property
            String accountId = envVar ?: System.getProperty(propKey)

            if (!accountId) {
                throw new IllegalStateException(
                    "Missing AWS account ID for ${env}. Set environment variable AWS_ACCOUNT_ID_${env.toUpperCase()} " +
                    "or Boomi property ${propKey}"
                )
            }

            if (!accountId.matches(/^\d{12}$/)) {
                throw new IllegalArgumentException(
                    "Invalid AWS account ID for ${env}: ${accountId}. Must be 12 digits."
                )
            }

            accountIds[env] = accountId
        }

        return accountIds
    }

    /**
     * Build role ARN from environment and account ID
     *
     * @param environment Target environment
     * @return Role ARN string
     */
    private String getRoleArn(String environment) {
        if (environment == "prod") {
            return null  // No AssumeRole needed for prod
        }

        String accountId = ACCOUNT_IDS[environment]
        if (!accountId) {
            throw new IllegalArgumentException("No account ID configured for environment: ${environment}")
        }

        return "arn:aws:iam::${accountId}:role/sml-elt-cross-account-${environment}"
    }

    /**
     * Create S3 client for target environment
     *
     * @param environment Target environment (prod/uat/dev/sit)
     * @return AmazonS3 client with appropriate credentials
     */
    private AmazonS3 createS3Client(String environment) {
        validateEnvironment(environment)

        if (environment == "prod") {
            // Production: use default credentials (IAM role attached to Boomi atom)
            return AmazonS3ClientBuilder.standard()
                .withRegion(REGION)
                .withCredentials(new DefaultAWSCredentialsProviderChain())
                .build()
        } else {
            // Non-prod: assume role in target account
            def credentials = assumeRole(environment)
            return AmazonS3ClientBuilder.standard()
                .withRegion(REGION)
                .withCredentials(new AWSStaticCredentialsProvider(credentials))
                .build()
        }
    }

    /**
     * Assume IAM role in target account
     *
     * @param environment Target environment
     * @return BasicSessionCredentials for assumed role
     */
    private BasicSessionCredentials assumeRole(String environment) {
        String roleArn = getRoleArn(environment)
        String externalId = EXTERNAL_IDS[environment]

        if (!roleArn) {
            throw new IllegalArgumentException("No role ARN configured for environment: ${environment}")
        }

        logInfo("Assuming role ${roleArn} for environment ${environment}")

        try {
            // Create STS client (uses default credentials from prod Boomi atom)
            AWSSecurityTokenService stsClient = AWSSecurityTokenServiceClientBuilder.standard()
                .withRegion(REGION)
                .withCredentials(new DefaultAWSCredentialsProviderChain())
                .build()

            // AssumeRole request
            AssumeRoleRequest assumeRoleRequest = new AssumeRoleRequest()
                .withRoleArn(roleArn)
                .withRoleSessionName("boomi-elt-session-${System.currentTimeMillis()}")
                .withDurationSeconds(3600)  // 1 hour

            if (externalId) {
                assumeRoleRequest.withExternalId(externalId)
            }

            AssumeRoleResult assumeRoleResult = stsClient.assumeRole(assumeRoleRequest)
            Credentials sessionCredentials = assumeRoleResult.getCredentials()

            logInfo("Successfully assumed role for ${environment}")

            return new BasicSessionCredentials(
                sessionCredentials.getAccessKeyId(),
                sessionCredentials.getSecretAccessKey(),
                sessionCredentials.getSessionToken()
            )
        } catch (Exception e) {
            logError("Failed to assume role for ${environment}", e)
            throw new RuntimeException("AssumeRole failed for ${environment}: ${e.message}", e)
        }
    }

    /**
     * Read object from S3
     *
     * @param environment Target environment (prod/uat/dev/sit)
     * @param key S3 object key (e.g., "documents/order-001.csv")
     * @return Object content as String
     */
    String readObject(String environment, String key) {
        AmazonS3 s3Client = createS3Client(environment)
        String bucketName = BUCKET_NAMES[environment]

        logInfo("Reading s3://${bucketName}/${key} from ${environment}")

        try {
            S3Object s3Object = s3Client.getObject(bucketName, key)
            String content = s3Object.getObjectContent().getText("UTF-8")

            logTelemetry("s3.read", environment, key, content.length())
            logInfo("Successfully read ${content.length()} bytes from s3://${bucketName}/${key}")

            return content
        } catch (Exception e) {
            logError("Failed to read s3://${bucketName}/${key} from ${environment}", e)
            logTelemetry("s3.read.error", environment, key, 0, e.message)
            throw new RuntimeException("Failed to read s3://${bucketName}/${key} from ${environment}: ${e.message}", e)
        }
    }

    /**
     * Write object to S3
     *
     * @param environment Target environment (prod/uat/dev/sit)
     * @param key S3 object key (e.g., "processed/order-001.csv")
     * @param content Content to write
     */
    void writeObject(String environment, String key, String content) {
        AmazonS3 s3Client = createS3Client(environment)
        String bucketName = BUCKET_NAMES[environment]

        logInfo("Writing ${content.length()} bytes to s3://${bucketName}/${key} in ${environment}")

        try {
            byte[] contentBytes = content.getBytes("UTF-8")
            ByteArrayInputStream inputStream = new ByteArrayInputStream(contentBytes)

            ObjectMetadata metadata = new ObjectMetadata()
            metadata.setContentLength(contentBytes.length)
            metadata.setContentType("text/plain; charset=UTF-8")

            PutObjectRequest putRequest = new PutObjectRequest(bucketName, key, inputStream, metadata)
            s3Client.putObject(putRequest)

            logTelemetry("s3.write", environment, key, contentBytes.length)
            logInfo("Successfully wrote ${contentBytes.length} bytes to s3://${bucketName}/${key}")
        } catch (Exception e) {
            logError("Failed to write s3://${bucketName}/${key} to ${environment}", e)
            logTelemetry("s3.write.error", environment, key, content.length(), e.message)
            throw new RuntimeException("Failed to write s3://${bucketName}/${key} to ${environment}: ${e.message}", e)
        }
    }

    /**
     * List objects in S3 bucket
     *
     * @param environment Target environment (prod/uat/dev/sit)
     * @param prefix Key prefix to filter (e.g., "documents/")
     * @return List of object keys
     */
    List<String> listObjects(String environment, String prefix = "") {
        AmazonS3 s3Client = createS3Client(environment)
        String bucketName = BUCKET_NAMES[environment]

        logInfo("Listing objects in s3://${bucketName}/${prefix} from ${environment}")

        try {
            ObjectListing objectListing = s3Client.listObjects(bucketName, prefix)
            List<String> keys = objectListing.getObjectSummaries().collect { it.getKey() }

            logTelemetry("s3.list", environment, prefix, keys.size())
            logInfo("Found ${keys.size()} objects in s3://${bucketName}/${prefix}")

            return keys
        } catch (Exception e) {
            logError("Failed to list s3://${bucketName}/${prefix} in ${environment}", e)
            logTelemetry("s3.list.error", environment, prefix, 0, e.message)
            throw new RuntimeException("Failed to list s3://${bucketName}/${prefix} in ${environment}: ${e.message}", e)
        }
    }

    /**
     * Delete object from S3
     *
     * @param environment Target environment (prod/uat/dev/sit)
     * @param key S3 object key
     */
    void deleteObject(String environment, String key) {
        AmazonS3 s3Client = createS3Client(environment)
        String bucketName = BUCKET_NAMES[environment]

        logInfo("Deleting s3://${bucketName}/${key} from ${environment}")

        try {
            s3Client.deleteObject(bucketName, key)

            logTelemetry("s3.delete", environment, key, 0)
            logInfo("Successfully deleted s3://${bucketName}/${key}")
        } catch (Exception e) {
            logError("Failed to delete s3://${bucketName}/${key} from ${environment}", e)
            logTelemetry("s3.delete.error", environment, key, 0, e.message)
            throw new RuntimeException("Failed to delete s3://${bucketName}/${key} from ${environment}: ${e.message}", e)
        }
    }

    /**
     * Check if object exists in S3
     *
     * @param environment Target environment (prod/uat/dev/sit)
     * @param key S3 object key
     * @return true if object exists, false otherwise
     */
    boolean objectExists(String environment, String key) {
        AmazonS3 s3Client = createS3Client(environment)
        String bucketName = BUCKET_NAMES[environment]

        try {
            boolean exists = s3Client.doesObjectExist(bucketName, key)
            logTelemetry("s3.exists", environment, key, exists ? 1 : 0)
            return exists
        } catch (Exception e) {
            logError("Failed to check existence of s3://${bucketName}/${key} in ${environment}", e)
            logTelemetry("s3.exists.error", environment, key, 0, e.message)
            throw new RuntimeException("Failed to check existence of s3://${bucketName}/${key} in ${environment}: ${e.message}", e)
        }
    }

    /**
     * Validate environment parameter
     *
     * @param environment Environment name
     * @throws IllegalArgumentException if environment is invalid
     */
    private void validateEnvironment(String environment) {
        if (!BUCKET_NAMES.containsKey(environment)) {
            throw new IllegalArgumentException("Invalid environment: ${environment}. Must be one of: ${BUCKET_NAMES.keySet()}")
        }
    }

    // ========== Telemetry and Logging ==========

    /**
     * Log telemetry event to SigNoz via OTLP
     *
     * Sends structured log with unified schema matching audit-log-contract.md:
     * - trace_id: Boomi execution ID
     * - action: s3.read/s3.write/s3.list/s3.delete/s3.exists
     * - resource_type: s3.object
     * - resource_id: s3://{bucket}/{key}
     * - meta: environment, bytes (for read/write)
     *
     * @param action Action type (e.g., "s3.read", "s3.write.error")
     * @param environment Target environment
     * @param key S3 object key
     * @param bytes Byte count (for read/write operations)
     * @param errorMessage Error message (for error events)
     */
    private void logTelemetry(String action, String environment, String key, long bytes = 0, String errorMessage = null) {
        try {
            def bucketName = BUCKET_NAMES[environment]
            def resourceId = "s3://${bucketName}/${key}"

            // Build telemetry payload matching unified logging schema
            def telemetryPayload = [
                trace_id: getBoomiExecutionId(),
                ip: getBoomiAtomIp(),
                time: new Date().format("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", TimeZone.getTimeZone("UTC")),
                action: action,
                error_code: errorMessage ? "S3_ERROR" : null,
                resource_type: "s3.object",
                resource_id: resourceId,
                user_id: "boomi-elt",
                message: errorMessage ?: "${action} on ${resourceId}",
                meta: [
                    environment: environment,
                    bytes: bytes,
                    bucket: bucketName,
                    key: key,
                    library_version: "1.0.0"
                ]
            ].findAll { k, v -> v != null }  // Remove null fields

            // Send to SigNoz OTLP endpoint (via ExecutionUtil or HTTP)
            sendToSigNoz(telemetryPayload)
        } catch (Exception e) {
            // Never fail the operation due to telemetry errors
            System.err.println("Failed to log telemetry for ${action}: ${e.message}")
        }
    }

    /**
     * Send telemetry to SigNoz OTLP HTTP endpoint
     *
     * @param payload Telemetry payload
     */
    private void sendToSigNoz(Map payload) {
        // Implementation depends on Boomi environment:
        // Option 1: Use ExecutionUtil.setDynamicProcessProperty + FluentBit sidecar
        // Option 2: Direct HTTP POST to SigNoz OTLP endpoint
        // Option 3: Write to stdout/stderr (captured by FluentBit)

        // For now, write to stdout as JSON (FluentBit will forward to SigNoz)
        println("TELEMETRY: ${groovy.json.JsonOutput.toJson(payload)}")
    }

    /**
     * Get Boomi execution ID (trace_id)
     */
    private String getBoomiExecutionId() {
        try {
            return com.boomi.execution.ExecutionUtil.getDynamicProcessProperty("document.dynamic.userdefined.execution_id") ?: "unknown"
        } catch (Exception e) {
            return "unknown"
        }
    }

    /**
     * Get Boomi atom IP address
     */
    private String getBoomiAtomIp() {
        try {
            return InetAddress.getLocalHost().getHostAddress()
        } catch (Exception e) {
            return "unknown"
        }
    }

    /**
     * Log info message
     */
    private void logInfo(String message) {
        println("[INFO] BoomiEltS3Library: ${message}")
    }

    /**
     * Log error message with exception
     */
    private void logError(String message, Exception e) {
        System.err.println("[ERROR] BoomiEltS3Library: ${message}")
        System.err.println("[ERROR] Exception: ${e.class.name}: ${e.message}")
        e.printStackTrace(System.err)
    }
}
