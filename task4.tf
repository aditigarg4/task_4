provider "aws" {
  region     = "ap-south-1"
  profile = "aditi"

}

resource "aws_vpc" "my_vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  enable_dns_support = "true"
  enable_dns_hostnames = "true"


  tags = {
    Name = "wp_vpc"
  }
}

resource "aws_internet_gateway" "wp_gw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "Internet_gateway"
  }

  depends_on = [ 
      aws_vpc.my_vpc,
    ]
}

resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.0.0/24"
  map_public_ip_on_launch = true
  availability_zone = "ap-south-1a"


  tags = {
    Name = "public_subnet"
  }

  depends_on = [ 
      aws_vpc.my_vpc,
      aws_internet_gateway.wp_gw
    ]
}


resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1b"


  tags = {
    Name = "private_subnet"
  }

  depends_on = [ 
      aws_subnet.public_subnet
    ]
}

resource "aws_route_table" "route_table1" {
  vpc_id = aws_vpc.my_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wp_gw.id
  }
  tags = {
    Name = "route_table"
    description = "route table for inbound traffic to vpc"
  }

  depends_on = [ 
      aws_vpc.my_vpc,
      aws_internet_gateway.wp_gw,
      aws_subnet.public_subnet 
    ]
}
resource "aws_route_table_association" "rt_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.route_table1.id
  depends_on = [ 
      aws_route_table.route_table1, 
      ]
}

resource "aws_eip" "my_eip" {
  vpc      = true
  tags = {
    Name = "first_eip"
  }
  depends_on = [
    aws_route_table_association.rt_association
  ]
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.my_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "gw NAT"
  }

  depends_on = [
    aws_eip.my_eip
  ]
}

resource "aws_route_table" "route_table2" {
  vpc_id = aws_vpc.my_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  tags = {
    Name = "route_table2"
    description = "route table for outbound traffic to private subnet"
  }

  depends_on = [ 
      aws_nat_gateway.nat_gw
    ]
}

resource "aws_route_table_association" "association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.route_table2.id
  depends_on = [ 
      aws_route_table.route_table2, 
      ]
}

resource "aws_security_group" "wordpress_sg" {
  name        = "wordpress"
  description = "allow TCP,ICMP-IPv4,HTTP,SSH to wordpress instance"
  vpc_id      = aws_vpc.my_vpc.id


  ingress {
    description = "Http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  ingress {
    description = "ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
   ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "wordpress_sg"
  }
  depends_on = [ 
      aws_route_table_association.association, 
      ]
}

resource "aws_security_group" "mysql_sg" {
  name        = "mysql"
  description = "connect to mysql instance"
  vpc_id      = aws_vpc.my_vpc.id


  ingress {
    description = "MYSQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sgroup_mysql"
  }

  depends_on = [ 
      aws_security_group.wordpress_sg, 
      ]
}

resource "tls_private_key" "mykey" {
  algorithm   = "RSA"
  rsa_bits = 4096
  
  depends_on = [
      aws_security_group.mysql_sg
      ]
}

resource "local_file" "private-key" {
    content     = tls_private_key.mykey.private_key_pem
    filename    = "tfkey.pem"
}

resource "aws_key_pair" "wp_key" {
  key_name   = "mykey18"
  public_key = tls_private_key.mykey.public_key_openssh

  depends_on = [
      tls_private_key.mykey
      ]
}

resource "aws_instance" "wordpress" {
  ami           = "ami-0732b62d310b80e97"
  instance_type = "t2.micro"
  key_name      =  aws_key_pair.wp_key.key_name
  subnet_id     = "${aws_subnet.public_subnet.id}"
  availability_zone = "ap-south-1a"
  vpc_security_group_ids = [ "${aws_security_group.wordpress_sg.id}" ]
  tags = {
    Name = "Wordpress_instance"
  }
  }
resource "null_resource" "wp-sql-connection" {
  depends_on = [
    aws_instance.mysql
  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.mykey.private_key_pem
    host     = aws_instance.wordpress.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo su <<END",
      "yum install docker httpd -y",
      "systemctl enable docker",
      "systemctl start docker",
      "docker pull wordpress:5.1.1-php7.3-apache",
      "sleep 30",
      "docker run -dit  -e WORDPRESS_DB_HOST=${aws_instance.mysql.private_ip} -e WORDPRESS_DB_USER=wpuser -e WORDPRESS_DB_PASSWORD=wppass -e WORDPRESS_DB_NAME=wpdb -p 80:80 wordpress:5.1.1-php7.3-apache",
      "END",
    ]
  }
  
  }



resource "aws_instance" "mysql" {
  depends_on = [
    aws_instance.wordpress
  ]
  ami           = "ami-0732b62d310b80e97"  
  instance_type = "t2.micro"
  subnet_id = aws_subnet.private_subnet.id
  security_groups = [aws_security_group.mysql_sg.id]
  # key_name = "key1"
  user_data = <<END
  #!/bin/bash
  sudo yum install mariadb-server mysql -y
  sudo systemctl enable mariadb.service
  sudo systemctl start mariadb.service
  mysql -u root <<EOF
  create user 'wpuser'@'${aws_instance.wordpress.private_ip}' identified by 'wppass';
  create database wpdb;
  grant all privileges on wpdb.* to 'wpuser'@'${aws_instance.wordpress.private_ip}';
  exit
  EOF
  END
 
  tags = {
    Name = "sql"
  }
}


resource "null_resource" "openwordpress"  {
depends_on = [
    null_resource.wp-sql-connection
  ]
	provisioner "local-exec" {
	    command = "start chrome  http://${aws_instance.wordpress.public_ip}/"
  	}
}
output "public_ip" {
    value = "${aws_instance.wordpress.public_ip}"
}

