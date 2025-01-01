provider "aws" {
  region = "us-east-2"
}

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type = number
  default = 8080
}

#Define the required data blocks for subnets and VPC
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
# configure security group of instances
resource "aws_security_group" "instance" {
  name = "my_terraform_project_instance"
  ingress {
    from_port = var.server_port
    to_port = var.server_port
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_launch_template" "example" {
  name_prefix   = "terraform-example-"
  image_id      = "ami-0fb653ca2d3203ac1"
  instance_type = "t2.micro"

  user_data = base64encode(<<-EOF
              #!/bin/bash
              mkdir -p /var/www/html
              echo "Hello, World" > /var/www/html/index.html
              nohup busybox httpd -f -p ${var.server_port} -h /var/www/html &              
  EOF
  )

  network_interfaces {
    security_groups = [aws_security_group.instance.id]
  }
}


# resource "aws_launch_configuration" "example" {
#   image_id = "ami-0fb653ca2d3203ac1"
#   instance_type = "t2.micro"
#   security_groups = [aws_security_group.instance.id]
  
#   user_data = <<-EOF
#               #!/bin/bash
#               mkdir -p /var/www/html
#               echo "Hello, World" > /var/www/html/index.html
#               nohup busybox httpd -f -p $${var.server_port} -h /var/www/html &              
#   EOF
  
#   # Required when using a launch configuration with an autoscaling group.
#   lifecycle {
#     create_before_destroy = true
#   }
# #   user_data_replace_on_change = true

  
# #   tags = {
# #     Name = "my_terraform_project"
# #   }
# }

output "alb_dns_name" {
  value = aws_lb.example.dns_name
  description = "The domain name of the load balancer"
}


# You’ll need to tell the aws_lb resource to use this security group via the security_groups argument
resource "aws_lb" "example" {
  name = "terraform-asg-example"
  load_balancer_type = "application"
  subnets = data.aws_subnets.default.ids
  security_groups = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port = 80
  protocol = "HTTP"
# By default, return a simple 404 page
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}

resource "aws_security_group" "alb" {
  name = "terraform-example-alb"
# Allow inbound HTTP requests
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
# Allow all outbound requests
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



#Next, you need to create a target group for your ASG using the aws_lb_target_group resource
resource "aws_lb_target_group" "asg" {
  name = "terraform-asg-example"
  port = var.server_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id
  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}

#creating listener rules using the aws_lb_listener_rule resource:
resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority = 100
  condition {
    path_pattern {
      values = ["*"]
    }
  }
  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

#configure autoscalling
resource "aws_autoscaling_group" "example" {
  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"
  }

  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns   = [aws_lb_target_group.asg.arn]
  health_check_type   = "ELB"

  min_size = 2
  max_size = 6

  tag {
    key                 = "Name"
    value               = "terraform-asg-example"
    propagate_at_launch = true
  }
}



# resource "aws_autoscaling_group" "example" {
#   launch_configuration = aws_launch_configuration.example.name
#   vpc_zone_identifier = data.aws_subnets.default.ids
  
#   target_group_arns = [aws_lb_target_group.asg.arn]
#   health_check_type = "ELB"

#   min_size = 2
#   max_size = 6

#   tag {
#     key = "Name"
#     value = "terraform-asg-example"
#     propagate_at_launch = true
#   }
# }