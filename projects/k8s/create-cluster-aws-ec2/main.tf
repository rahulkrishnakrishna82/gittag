provider "aws" {
  region = "us-east-1"
}

module "ec2_instance" {
  source = "./modules/ec2"

  instance_name = "k8s-node"
  # Check the AMI at https://cloud-images.ubuntu.com/locator/ec2/
  ami_id = "ami-0c7217cdde317cfec"
  # instance_type  = "t2.medium"
  instance_type  = "t2.small"
  key_name       = "k8sclusterawsv1"
  subnet_ids     = ["subnet-0bd490b41b8a806d8", "subnet-05e405bb009af9fc0", "subnet-0890390acefca267a"]
  instance_count = 3

  inbound_rules = [
    {
      from_port  = 0
      to_port    = 65000
      protocol   = "TCP"
      cidr_block = "172.31.0.0/16"
    },
    {
      from_port  = 6443
      to_port    = 6443
      protocol   = "TCP"
      cidr_block = "0.0.0.0/0"
    },
    {
      from_port  = 22
      to_port    = 22
      protocol   = "TCP"
      cidr_block = "0.0.0.0/0"
    },
    {
      from_port  = 30000
      to_port    = 32768
      protocol   = "TCP"
      cidr_block = "0.0.0.0/0"
    }
  ]

  outbound_rules = [
    {
      from_port  = 0
      to_port    = 0
      protocol   = "-1"
      cidr_block = "0.0.0.0/0"
    }
  ]
}

output "public_ips" {
  value = module.ec2_instance.public_ips
}

# Initialize the k8s controller
resource "null_resource" "execute_k8s_master" {
  provisioner "local-exec" {
    # command = "ssh -o StrictHostKeyChecking=no -i ${var.private_key_path} ubuntu@${module.ec2_instance.public_ips[0]} bash < scripts/local_script.sh"
    command = <<EOF
      echo "Preparing k8s master"
      sleep 120; ssh -o StrictHostKeyChecking=no -i ${var.private_key_path} ubuntu@${module.ec2_instance.public_ips[0]} bash < scripts/k8s_master.sh
      echo "Prepair completed for Kubernetes cluster"
    EOF
  }
}

# K8s checker
resource "null_resource" "execute_k8s_master_checker" {
  depends_on = [null_resource.execute_k8s_master]
  provisioner "local-exec" {
    command = <<EOF
      echo "Check k8s master"
      ssh -o StrictHostKeyChecking=no -i ${var.private_key_path} ubuntu@${module.ec2_instance.public_ips[0]} bash < scripts/k8s_master_checker.sh
      echo "Check k8s master completed"
    EOF
  }
}

# K8s generate token
resource "null_resource" "k8s_master_generate_token" {
  depends_on = [null_resource.execute_k8s_master_checker]
  provisioner "local-exec" {
    command = <<EOF
      echo "k8s_master_generate_token"
      ssh -o StrictHostKeyChecking=no -i ${var.private_key_path} ubuntu@${module.ec2_instance.public_ips[0]} bash < scripts/k8s_master_generate_token.sh > /tmp/token_output.txt
      echo "k8s_master_generate_token completed"
    EOF
  }
}

data "local_file" "output_file" {
  depends_on = [null_resource.k8s_master_generate_token]
  filename   = "/tmp/token_output.txt"
}

# output "command_output" {
#   depends_on = [null_resource.k8s_master_generate_token]
#   value      = data.local_file.output_file.content
# }

# Get k8s token
resource "null_resource" "check_token_output" {
  depends_on = [null_resource.k8s_master_generate_token]
  provisioner "local-exec" {
    command = "cat /tmp/token_output.txt"
  }
}

locals {
  depends_on      = [null_resource.k8s_master_generate_token]
  cleaned_content = replace(data.local_file.output_file.content, "\nEOT", "")
}

output "cleaned_output" {
  value = local.cleaned_content
}

# [Worker] Join worker to k8s cluster
resource "null_resource" "k8s_worker_join_1" {
  depends_on = [null_resource.k8s_master_generate_token]
  provisioner "local-exec" {
    command = <<EOF
      echo "Starting worker join process for Kubernetes cluster"
      ssh -o StrictHostKeyChecking=no -i ${var.private_key_path} ubuntu@${module.ec2_instance.public_ips[1]} bash < scripts/k8s_worker_join.sh "${local.cleaned_content}"
      echo "Worker join process completed for Kubernetes cluster"
    EOF
  }
}


# [Worker] Join worker to k8s cluster
resource "null_resource" "k8s_worker_join_2" {
  depends_on = [null_resource.k8s_master_generate_token]
  provisioner "local-exec" {
    command = <<EOF
      echo "Starting worker join process for Kubernetes cluster"
      ssh -o StrictHostKeyChecking=no -i ${var.private_key_path} ubuntu@${module.ec2_instance.public_ips[2]} bash < scripts/k8s_worker_join.sh "${local.cleaned_content}"
      echo "Worker join process completed for Kubernetes cluster"
    EOF
  }
}


# K8s checker at the end
resource "null_resource" "execute_k8s_master_checker_again" {
  depends_on = [null_resource.execute_k8s_master]
  provisioner "local-exec" {
    command = <<EOF
      echo "Check k8s master"
      ssh -o StrictHostKeyChecking=no -i ${var.private_key_path} ubuntu@${module.ec2_instance.public_ips[0]} bash < scripts/k8s_master_checker.sh
      echo "Check k8s master completed"
    EOF
  }
}