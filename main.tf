terraform {
  required_providers {
    kubernetes = {}
    jenkins = {
      source  = "taiidani/jenkins"
      version = "~> 0.9.0"
    }
    spinnaker = {
      source  = "tidal-engineering/spinnaker"
      version = "1.0.6"
    }
  }
}

locals {
  name = "react-microservice-build"
  jenkins_microservice_build_job = templatefile("${path.module}/scripts/jenkins-project.tpl", {
    kubectl_version = var.kubectl_version
    }
  )
}

locals {
  spinnaker_pipeline = templatefile("${path.module}/scripts/spinnaker-pipeline.tpl", {
    jenkins_job_name = local.name
    github_hook_pw   = var.github_hook_pw
    }
  )
}

resource "jenkins_job" "microservice-build" {
  name     = local.name
  template = local.jenkins_microservice_build_job
}

resource "spinnaker_application" "application" {
  application = "react-microservice-template"
  email       = "anorris@rivasolutionsinc.com"
}

resource "spinnaker_pipeline" "pipeline" {
  application = spinnaker_application.application.application
  name        = "build and deploy"
  pipeline    = local.spinnaker_pipeline

  depends_on = [
    jenkins_job.microservice-build
  ]
}
