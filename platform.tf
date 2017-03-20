
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "zoneid" {}

provider "aws" {
    access_key = "${var.aws_access_key}"
    secret_key = "${var.aws_secret_key}"
    region = "eu-west-1"
}

resource "aws_s3_bucket" "s3_bucket_a" {
  bucket = "cloudcauldron.io"
  acl = "public-read"
  website {
      index_document = "index.html"
      error_document = "404.html"
  }
  policy = <<EOF
{
  "Id": "Policy1486774110599",
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Stmt1486774100096",
      "Action": [
        "s3:GetObject"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::cloudcauldron.io/*",
      "Principal": "*"
    }
  ]
}
EOF
}

resource "aws_s3_bucket" "s3_bucket_b" {
  bucket = "cloudcauldron.io-access-logs"
  acl = "private"
}

# All the security gubbins needed by Lambda
resource "aws_iam_role" "hugolambdaexecrole" {
  name               = "HugoLambdaExecRole"
  assume_role_policy = "${file("${path.module}/policies/lambda_role.json")}"
}

resource "aws_iam_instance_profile" "hugolambdaexecprofile" {
  name  = "HugoLambdaExecProfile"
  roles = ["${aws_iam_role.hugolambdaexecrole.id}"]
}

resource "aws_iam_policy" "hugolambdaexecpolicy" {
  name   = "HugoLambdaExecPolicy"
  policy = "${file("${path.module}/policies/AccessToHugoS3Buckets.json")}"
}

resource "aws_iam_policy_attachment" "HugoLambdaExecRole" {
  name       = "HugoLambdaExecRole"
  roles      = ["${aws_iam_role.hugolambdaexecrole.id}"]
  policy_arn = "${aws_iam_policy.hugolambdaexecpolicy.arn}"
}

# Lambda Resource #
resource "aws_lambda_function" "run_hugo_lambda" {
  filename         = "run_hugo.zip"
  source_code_hash = "${base64sha256("run_hugo.zip")}"
  function_name    = "run_hugo"
  description      = "Hugo State Site Generation"
  timeout          = "30"
  runtime          = "python2.7"
  handler          = "run_hugo.lambda_handler"
  memory_size      = "128"
  role             = "${aws_iam_role.hugolambdaexecrole.arn}"
}

resource "aws_route53_record" "hostname" {
  zone_id = "${var.zoneid}"
  name = "cloudcauldron.io"
  type = "A"
  alias {
    name = "${aws_cloudfront_distribution.s3_distribution.domain_name}"
    zone_id = "${aws_cloudfront_distribution.s3_distribution.hosted_zone_id}"  # always Z2FDTNDATAQYW2
    evaluate_target_health = false
  }
}


resource "aws_cloudfront_distribution" "s3_distribution" {
  # Terraform forces the proper bucket address.
  # However, this doesn't work properly.  Subfolders
  # can't detect the index.html in each one.  The 
  # hardcoded values works but you must set it in AWS
  # console.
  origin {
    # It will want to set it to: cloudcauldron.io.s3.amazonaws.com
    # this won't work correctly. So hardcoding.
    domain_name = "${aws_s3_bucket.s3_bucket_a.bucket_domain_name}"
    #domain_name = "cloudcauldron.io.s3-website-eu-west-1.amazonaws.com"
    origin_id   = "S3-cloudcauldron.io"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "This is cloudcauldron.io"
  default_root_object = "index.html"

  logging_config {
    bucket          = "cloudcauldron.io-access-logs.s3.amazonaws.com"
  }

  aliases = ["*.cloudcauldron.io", "cloudcauldron.io"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-cloudcauldron.io"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    compress = true

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
    #acm_certificate_arn = "${data.aws_acm_certificate.cloudcauldron.arn}"
    acm_certificate_arn = "arn:aws:acm:us-east-1:894121584238:certificate/0fdf4145-47a3-441e-85b1-d257ad74628f"
    minimum_protocol_version = "TLSv1"
    ssl_support_method = "sni-only"
  }
}


#data "aws_acm_certificate" "cloudcauldron" {
#  domain = "cloudcauldron.io"
#  statuses = ["ISSUED"]
#}
