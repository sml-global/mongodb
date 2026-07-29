import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
NETWORK_MAIN = REPO_ROOT / "platform-prerequisites/terraform/modules/network/main.tf"
NETWORK_OUTPUTS = REPO_ROOT / "platform-prerequisites/terraform/modules/network/outputs.tf"


class S3GatewayEndpointTests(unittest.TestCase):
    def test_s3_gateway_endpoint_resource_exists(self):
        text = NETWORK_MAIN.read_text(encoding="utf-8")
        self.assertIn('resource "aws_vpc_endpoint" "s3"', text)
        self.assertIn('vpc_endpoint_type = "Gateway"', text)

    def test_s3_endpoint_attaches_to_private_and_database_route_tables(self):
        text = NETWORK_MAIN.read_text(encoding="utf-8")
        self.assertIn("aws_route_table.private", text)
        self.assertIn("aws_route_table.database", text)

    def test_s3_endpoint_id_output_exists(self):
        text = NETWORK_OUTPUTS.read_text(encoding="utf-8")
        self.assertIn('output "s3_vpc_endpoint_id"', text)


if __name__ == "__main__":
    unittest.main()
