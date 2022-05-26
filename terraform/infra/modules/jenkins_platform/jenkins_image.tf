data "aws_ecr_authorization_token" "token" {}

locals {
  ecr_endpoint = split("/", aws_ecr_repository.jenkins_controller.repository_url)[0]
}


resource "aws_ecr_repository" "jenkins_controller" {
  name                 =  var.jenkins_ecr_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration  {
      scan_on_push = true
  }

}

# image for agent
resource "aws_ecr_repository" "jenkins_agent" {
  name                 = var.jenkins_agent_ecr_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

data "template_file" jenkins_configuration_def {

  template = file("${path.module}/docker/files/jenkins.yaml.tpl")

  vars = {
    ecs_cluster_fargate       = aws_ecs_cluster.jenkins_controller.arn
    ecs_cluster_fargate_spot  = aws_ecs_cluster.jenkins_agents.arn
    cluster_region            = local.region
    jenkins_cloud_map_name    = "controller.infra"
    jenkins_controller_port   = var.jenkins_controller_port
    jnlp_port                 = var.jenkins_jnlp_port
    agent_security_groups     = aws_security_group.jenkins_controller_security_group.id
    execution_role_arn        = aws_iam_role.ecs_execution_role.arn
    subnets                   = join(",", var.jenkins_controller_subnet_ids)
    ec2builder_image          = aws_ecr_repository.jenkins_agent.repository_url
    ec2_capacity_provider     = aws_ecs_capacity_provider.jenkins_slave_ec2_provider.name
    log_group                 = var.name_prefix
  }
}


resource "null_resource" "render_template" {
  triggers = {
    src_hash = file("${path.module}/docker/files/jenkins.yaml.tpl")
  }
  depends_on = [data.template_file.jenkins_configuration_def]

  provisioner "local-exec" {
    command = <<EOF
tee ${path.module}/docker/files/jenkins.yaml <<ENDF
${data.template_file.jenkins_configuration_def.rendered}
EOF
  }
}

resource "null_resource" "build_docker_image" {
  triggers = {
     src_hash = file("${path.module}/docker/files/jenkins.yaml.tpl")
  }
  depends_on = [null_resource.render_template]
  provisioner "local-exec" {
    command = <<EOF
docker login -u AWS -p ${data.aws_ecr_authorization_token.token.password} ${local.ecr_endpoint} && \
docker build -t ${aws_ecr_repository.jenkins_controller.repository_url}:latest ${path.module}/docker/ && \
docker push ${aws_ecr_repository.jenkins_controller.repository_url}:latest
EOF
  }
}

resource "null_resource" "build_agent_docker_image" {
  triggers = {
    src_hash = filebase64sha256("${path.module}/docker/agent/Dockerfile")
  }
  provisioner "local-exec" {
    command = <<EOF
docker login -u AWS -p ${data.aws_ecr_authorization_token.token.password} ${local.ecr_endpoint} && \
docker build -t ${aws_ecr_repository.jenkins_agent.repository_url}:latest ${path.module}/docker/agent/ && \
docker push ${aws_ecr_repository.jenkins_agent.repository_url}:latest
EOF
  }
}

