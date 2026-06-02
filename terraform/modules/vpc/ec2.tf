#############################
# Security Group
#############################
resource "aws_security_group" "ec2_sg" {
  name        = "${var.tool}-sg"
  description = "Security group for ${var.tool} EC2"
  vpc_id      = aws_vpc.dockervpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Jenkins HTTP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SonarQube HTTP"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.tool}-sg" }
}

#############################
# Jenkins / DevOps EC2
#############################
resource "aws_instance" "ec2_jenkins" {
  ami                         = var.ec2_ami
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.dockerpubsub.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = <<EOF
#cloud-config
package_update: true
package_upgrade: true
packages:
  - java-21-amazon-corretto
  - docker
runcmd:
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker ec2-user
  - curl -fsSL https://pkg.jenkins.io/redhat-stable/jenkins.io.key | tee /etc/pki/rpm-gpg/RPM-GPG-KEY-jenkins
  - curl -fsSL https://pkg.jenkins.io/redhat-stable/jenkins.repo -o /etc/yum.repos.d/jenkins.repo
  - dnf install -y jenkins
  - systemctl enable jenkins
  - systemctl start jenkins
  - curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  - install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  - curl -sL "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
  - mv /tmp/eksctl /usr/local/bin
  - chmod +x /usr/local/bin/eksctl
  - curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  - dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
EOF

  tags = {
    Name = "jenkins-docker"
  }
}

#############################
# SonarQube EC2
#############################
resource "aws_instance" "ec2_sonarqube" {
  ami                         = var.ec2_ami  
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.dockerpubsub.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = <<EOF
#!/bin/bash
set -euxo pipefail
exec > /var/log/user-data.log 2>&1

echo "Starting SonarQube userdata at \$(date)"

# Update system
yum update -y

# Install Docker
yum install -y docker

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Wait for Docker to be ready
until docker info >/dev/null 2>&1; do
  echo "Waiting for Docker..."
  sleep 3
done

# Pull and run SonarQube container
docker pull sonarqube:lts
docker run -d --name sonarqube -p 9000:9000 sonarqube:lts

echo "SonarQube container started successfully at \$(date)"
EOF

  tags = {
    Name = "sonarqube-docker"
  }
}
