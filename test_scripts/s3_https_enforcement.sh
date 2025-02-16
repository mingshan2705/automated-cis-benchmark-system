#!/bin/bash

# Ensure AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install AWS CLI before running this script."
    exit 1
fi

# Get list of all S3 buckets
echo "🔍 Fetching list of S3 buckets..."
BUCKETS=$(aws s3api list-buckets --query "Buckets[].Name" --output text)

if [[ -z "$BUCKETS" ]]; then
    echo "❌ No S3 buckets found in your AWS account."
    exit 1
fi

# Iterate through each bucket
for BUCKET in $BUCKETS; do
    echo "🔎 Checking bucket: $BUCKET"

    # Get current bucket policy
    POLICY=$(aws s3api get-bucket-policy --bucket "$BUCKET" --query Policy --output text 2>/dev/null)

    if [[ -z "$POLICY" ]]; then
        echo "⚠ No policy found for $BUCKET. It allows both HTTP and HTTPS requests."
    else
        # Check if policy enforces HTTPS
        if echo "$POLICY" | grep -q "aws:SecureTransport"; then
            echo "✅ $BUCKET already enforces HTTPS."
            continue
        else
            echo "❌ $BUCKET does NOT enforce HTTPS. Updating policy..."
        fi
    fi

    # Generate new policy to enforce HTTPS
    cat > policy.json <<EOL
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyHTTPAccess",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": "arn:aws:s3:::$BUCKET/*",
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        },
        {
            "Sid": "DenyOldTLS",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::$BUCKET",
                "arn:aws:s3:::$BUCKET/*"
            ],
            "Condition": {
                "NumericLessThan": {
                    "s3:TlsVersion": "1.2"
                }
            }
        }
    ]
}
EOL

    # Apply the policy to the bucket
    aws s3api put-bucket-policy --bucket "$BUCKET" --policy file://policy.json

    echo "✅ Updated bucket policy for $BUCKET to enforce HTTPS and TLS 1.2+"
done

# Cleanup temporary policy file
rm -f policy.json

echo "🎉 Compliance check completed!"
