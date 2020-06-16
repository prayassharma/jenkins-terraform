provider  "aws"  {
  region  = "ap-south-1"
  profile   ="prayas"
}

#generating key pair
resource "tls_private_key" "key_terraform" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "aws_key_pair" "key_terraform" {
  key_name   = "key_terraform"
  public_key = tls_private_key.key_terraform.public_key_openssh
}

# saving key to local file
resource "local_file" "key_terraform" {
    content  = tls_private_key.key_terraform.private_key_pem
    filename = "/root/terraform/key_terraform.pem"
}

#default vpc

data "aws_vpc" "selected" {
    default = true
}
locals {
    vpc_id    = data.aws_vpc.selected.id
}

#creating security group
resource "aws_security_group" "SG_terraform" {
    name        = "SG_terraform"
    description = "https, ssh"
    vpc_id      = local.vpc_id
	
#rules for security group

ingress {
        description = "http"
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    
    ingress {
        description = "ssh"
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
tags = {
        Name = "SG_terraform"
    }
}


resource "aws_instance" "os_terraform" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = aws_key_pair.key_terraform.key_name
  vpc_security_group_ids  = [aws_security_group.SG_terraform.id]
  subnet_id               = "subnet-aae2d8c2"
  availability_zone       = "ap-south-1a"

  connection {	
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.key_terraform.private_key_pem
    host     = aws_instance.os_terraform.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo amazon-linux-extras install ansible2 -y",
	  "sudo wget https://raw.githubusercontent.com/prayassharma/ansible/master/pkgs.yml",
	  "sudo ansible-playbook pkgs.yml",
    ]
  }

  tags = {
    Name = "os_terraform"
  }

}

resource "aws_ebs_volume" "volume_terraform" {
    availability_zone = aws_instance.os_terraform.availability_zone
    size              = 1
    tags = {
        Name = "volume_terraform"
    }
}
resource "aws_volume_attachment" "attach_volume" {
    device_name = "/dev/sdh"
    volume_id   = aws_ebs_volume.volume_terraform.id
    instance_id = aws_instance.os_terraform.id
}
output "my_instance_ip" {
  value = aws_instance.os_terraform.public_ip
}


resource "null_resource" "nulllocal2"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.os_terraform.public_ip} > publicip.txt"
  	}
}



resource "null_resource" "nullremote3"  {

depends_on = [
    aws_volume_attachment.attach_volume,
  ]
	
	
	connection {
        type    = "ssh"
        user    = "ec2-user"
        private_key = tls_private_key.key_terraform.private_key_pem
		host    = aws_instance.os_terraform.public_ip
    }    
	
provisioner "remote-exec" {
        inline  = [
          "sudo wget https://raw.githubusercontent.com/prayassharma/ansible/master/filesystem.yml",
	      "sudo ansible-playbook filesystem.yml",
        ]
    }
}



resource "aws_s3_bucket" "s3-bucket-terraform" {
depends_on = [aws_volume_attachment.attach_volume,]
    bucket  = "s3-bucket-terraform"
    acl     = "public-read"
provisioner "local-exec" {
        command     = "git clone https://github.com/prayassharma/terraform_data webpage"
    }
provisioner "local-exec" {
        when        =   destroy
        command     =   "echo Y | rmdir /s webpage"
    }
}
resource "aws_s3_bucket_object" "s3_bucket_terraform_upload" {
    bucket  = aws_s3_bucket.s3-bucket-terraform.bucket
    key     = "aws.jpg"
    source  = "webpage/aws.jpg"
    acl     = "public-read"
}

resource "aws_s3_bucket_object"  "object" { 
   bucket = "${aws_s3_bucket.s3-bucket-terraform.id}" 
   key = "aws.jpg" 
   source = "webpage/aws.jpg" 
   acl="public-read"
} 
locals {
  s3_origin_id = "prayassharmaa"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.s3-bucket-terraform.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Cloud front for continous delivery"
  default_root_object = "index.html"

restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  } 

 tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "null_resource" "nullremote4" { 
connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = "${tls_private_key.key_terraform.private_key_pem}"
    host     = aws_instance.os_terraform.public_ip
  }
provisioner "remote-exec"{ 
inline=[ "sudo su <<EOF",
         "echo \"<img src= 'http://${aws_cloudfront_distribution.s3_distribution.domain_name}/aws.jpg' height='300'>\"  >> /var/www/html/index.html",
		 "EOF",
] 
} 
provisioner "local-exec" {
command = "start brave ${aws_instance.os_terraform.public_ip}"
}
}
 




