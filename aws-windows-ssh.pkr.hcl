packer {
  required_plugins {
    amazon         = { source = "github.com/hashicorp/amazon",         version = "1.4.0" }
    ansible        = { source = "github.com/hashicorp/ansible",        version = "1.1.4" }
  }
}


variable "ami_name_prefix" {
  type    = string
  default = "windows-base-2022"
}

variable "image_name" {
  type    = string
  default = "Windows Server 2022 image with ssh"
}

locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

data "amazon-ami" "aws-windows-ssh" {
  filters = {
    name                = "Windows_Server-2022-English-Full-Base-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
}

source "amazon-ebs" "aws-windows-ssh" {
  source_ami                  = "${data.amazon-ami.aws-windows-ssh.id}"
  ami_name                    = "${var.ami_name_prefix}-HRSPRINT-${local.timestamp}"
  ami_description             = "${var.image_name}"
  ami_virtualization_type     = "hvm"
  associate_public_ip_address = true
  communicator                = "ssh"
  iam_instance_profile        = "EC2InstanceProfile"
  vpc_id                      = "vpc-0a370323017b4462d"
  subnet_id                   = "subnet-02da2db96a6b063ac"
  security_group_id           = "sg-067d2714bf88d136b"
  instance_type               = "c5a.large"
  winrm_timeout               = "10m"
  ssh_username                = "Administrator"
  ssh_file_transfer_method    = "scp"
  user_data_file              = "files/SetupSsh.ps1"
  metadata_options {
    http_endpoint = "enabled"
    http_tokens = "optional"
    http_put_response_hop_limit = 1
    instance_metadata_tags = "enabled"
  }

  fast_launch {
    enable_fast_launch = false
  }
  
  snapshot_tags = {
    Name      = "${var.image_name}"
    BuildTime = "${local.timestamp}"
    OSType    = "Windows"
    Usage     = "HRSPRINT"
  }

  tags = {
    Name      = "${var.image_name}"
    BuildTime = "${local.timestamp}"
  }
}

build {
  sources = ["source.amazon-ebs.aws-windows-ssh"]

  provisioner "powershell" {
    script = "files/InstallChoco.ps1"
  }

provisioner "powershell" {
  inline = ["New-Item -ItemType Directory -Path C://Exploitation"]
}

provisioner "ansible" {
playbook_file = "files/playbook.yaml"
user = "Administrator"
use_proxy = false
extra_arguments = [
    "-e", "ansible_user=Administrator",
    "-e", "ansible_connection=ssh",
    "-e", "ansible_shell_type=powershell"
]
}

provisioner "windows-restart" {
  restart_check_command = "powershell -command \"& {Write-Output 'restarted.'}\""
}


  provisioner "powershell" {
    script = "files/PrepareImage.ps1"
  }
}

