resource "kubernetes_deployment" "deploy_app" {
  wait_for_rollout = var.wait_for_rollout

  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = local.labels
    annotations = var.deployment_annotations
  }

  spec {
    min_ready_seconds = var.min_ready_seconds
    replicas          = var.replicas

    strategy {
      type = var.strategy_update
      dynamic "rolling_update" {
        for_each = flatten([var.rolling_update])
        content {
          max_surge       = rolling_update.value.max_surge
          max_unavailable = rolling_update.value.max_unavailable
        }
      }
    }

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels      = local.labels
        annotations = var.template_annotations
      }

      spec {
        termination_grace_period_seconds = var.termination_grace_period_seconds

        service_account_name            = var.service_account_name
        automount_service_account_token = var.service_account_token

        restart_policy = var.restart_policy
        
        dynamic "image_pull_secrets" {
          for_each = var.image_pull_secrets
          content {
            name = image_pull_secrets.value
          }
        }

        node_selector = var.node_selector

        dynamic "affinity" {
          for_each = var.prevent_deploy_on_the_same_node ? [{}] : []
          content {
            pod_anti_affinity {
              required_during_scheduling_ignored_during_execution {
                label_selector {
                  match_labels = local.labels
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }

        dynamic "toleration" {
          for_each = var.toleration
          content {
            effect             = toleration.value.effect
            key                = toleration.value.key
            operator           = toleration.value.operator
            toleration_seconds = toleration.value.toleration_seconds
            value              = toleration.value.value
          }
        }

        dynamic "host_aliases" {
          iterator = hosts
          for_each = var.hosts
          content {
            hostnames = hosts.value.hostname
            ip        = hosts.value.ip
          }
        }

        dynamic "volume" {
          for_each = var.volume_empty_dir
          content {
            empty_dir {
              medium     = volume.value.medium
              size_limit = volume.value.size_limit
            }
            name = volume.value.volume_name
          }
        }

        dynamic "volume" {
          for_each = var.volume_nfs
          content {
            nfs {
              path   = volume.value.path_on_nfs
              server = volume.value.nfs_endpoint
            }
            name = volume.value.volume_name
          }
        }

        dynamic "volume" {
          for_each = var.volume_host_path
          content {
            host_path {
              path = volume.value.path_on_node
              type = volume.value.type
            }
            name = volume.value.volume_name
          }
        }

        dynamic "volume" {
          for_each = var.volume_config_map
          content {
            config_map {
              default_mode = volume.value.mode
              name         = volume.value.name
              optional     = volume.value.optional
              dynamic "items" {
                for_each = volume.value.items
                content {
                  key  = items.value.key
                  path = items.value.path
                  mode = items.value.mode
                }
              }
            }
            name = volume.value.volume_name
          }
        }

        dynamic "volume" {
          for_each = var.volume_gce_disk
          content {
            gce_persistent_disk {
              pd_name   = volume.value.gce_disk
              fs_type   = volume.value.fs_type
              partition = volume.value.partition
              read_only = volume.value.read_only
            }
            name = volume.value.volume_name
          }
        }

        dynamic "volume" {
          for_each = var.volume_secret
          content {
            secret {
              secret_name  = volume.value.secret_name
              default_mode = volume.value.default_mode
              optional     = volume.value.optional
              dynamic "items" {
                for_each = volume.value.items
                content {
                  key  = items.value.key
                  path = items.value.path
                  mode = items.value.mode
                }
              }
            }
            name = volume.value.volume_name
          }
        }

        dynamic "volume" {
          for_each = var.volume_aws_disk
          content {
            aws_elastic_block_store {
              fs_type   = volume.value.fs_type
              partition = volume.value.partition
              read_only = volume.value.read_only
              volume_id = volume.value.volume_id
            }
            name = volume.value.volume_name
          }
        }

        dynamic "volume" {
          for_each = var.volume_claim
          content {
            persistent_volume_claim {
              claim_name = volume.value.claim_name
              read_only  = volume.value.read_only
            }
            name = volume.value.volume_name
          }
        }

        dynamic "security_context" {
          for_each = flatten([var.security_context])
          content {
            fs_group        = security_context.value.fs_group
            run_as_group    = security_context.value.run_as_group
            run_as_user     = security_context.value.run_as_user
            run_as_non_root = security_context.value.run_as_non_root
          }
        }

        container {
          name              = var.name
          image             = var.image
          image_pull_policy = var.image_pull_policy
          args              = var.args
          command           = var.command

          dynamic "security_context" {
            for_each = flatten([var.security_context_container])
            content {
              allow_privilege_escalation = security_context.value.allow_privilege_escalation
              privileged                 = security_context.value.privileged
              read_only_root_filesystem  = security_context.value.read_only_root_filesystem
              dynamic "capabilities" {
                for_each = security_context.value.capabilities != null ? [security_context.value.capabilities] : []
                content {
                  add  = capabilities.value.add
                  drop = capabilities.value.drop
                }
              }
            }
          }

          dynamic "env" {
            for_each = local.env
            content {
              name  = env.value.name
              value = env.value.value
            }
          }

          dynamic "env" {
            for_each = local.env_field
            content {
              name = env.value.name
              value_from {
                field_ref {
                  field_path = env.value.field_path
                }
              }
            }
          }

          dynamic "env" {
            for_each = local.env_secret
            content {
              name = env.value.name
              value_from {
                secret_key_ref {
                  name = env.value.secret_name
                  key  = env.value.secret_key
                }
              }
            }
          }

          dynamic "resources" {
            for_each = length(var.resources) == 0 ? [] : [{}]
            content {
              requests = {
                cpu    = var.resources.request_cpu
                memory = var.resources.request_memory
              }
              limits = {
                cpu    = var.resources.limit_cpu
                memory = var.resources.limit_memory
              }
            }
          }

          dynamic "port" {
            for_each = var.internal_port
            content {
              container_port = port.value.internal_port
              name           = substr(port.value.name, 0, 14)
              host_port      = port.value.host_port
            }
          }

          dynamic "volume_mount" {
            for_each = var.volume_mount
            content {
              mount_path = volume_mount.value.mount_path
              sub_path   = volume_mount.value.sub_path
              name       = volume_mount.value.volume_name
              read_only  = volume_mount.value.read_only
            }
          }

          dynamic "liveness_probe" {
            for_each = flatten([var.liveness_probe])
            content {
              initial_delay_seconds = liveness_probe.value.initial_delay_seconds
              period_seconds        = liveness_probe.value.period_seconds
              timeout_seconds       = liveness_probe.value.timeout_seconds
              success_threshold     = liveness_probe.value.success_threshold
              failure_threshold     = liveness_probe.value.failure_threshold

              dynamic "http_get" {
                for_each = liveness_probe.value.http_get != null ? [liveness_probe.value.http_get] : []

                content {
                  path   = http_get.value.path
                  port   = http_get.value.port
                  scheme = http_get.value.scheme
                  host   = http_get.value.host

                  dynamic "http_header" {
                    for_each = http_get.value.http_header != null ? http_get.value.http_header : []
                    content {
                      name  = http_header.value.name
                      value = http_header.value.value
                    }
                  }

                }
              }

              dynamic "exec" {
                for_each = liveness_probe.value.exec != null ? [liveness_probe.value.exec] : []

                content {
                  command = exec.value.command
                }
              }

              dynamic "tcp_socket" {
                for_each = liveness_probe.value.tcp_socket != null ? [liveness_probe.value.tcp_socket] : []
                content {
                  port = tcp_socket.value.port
                }
              }
            }
          }

          dynamic "readiness_probe" {
            for_each = flatten([var.readiness_probe])
            content {
              initial_delay_seconds = readiness_probe.value.initial_delay_seconds
              period_seconds        = readiness_probe.value.period_seconds
              timeout_seconds       = readiness_probe.value.timeout_seconds
              success_threshold     = readiness_probe.value.success_threshold
              failure_threshold     = readiness_probe.value.failure_threshold

              dynamic "http_get" {
                for_each = readiness_probe.value.http_get != null ? [readiness_probe.value.http_get] : []

                content {
                  path   = http_get.value.path
                  port   = http_get.value.port
                  scheme = http_get.value.scheme
                  host   = http_get.value.host

                  dynamic "http_header" {
                    for_each = http_get.value.http_header != null ? http_get.value.http_header : []
                    content {
                      name  = http_header.value.name
                      value = http_header.value.value
                    }
                  }
                }
              }

              dynamic "exec" {
                for_each = readiness_probe.value.exec != null ? [readiness_probe.value.exec] : []

                content {
                  command = exec.value.command
                }
              }

              dynamic "tcp_socket" {
                for_each = readiness_probe.value.tcp_socket != null ? [readiness_probe.value.tcp_socket] : []
                content {
                  port = tcp_socket.value.port
                }
              }
            }
          }

          dynamic "lifecycle" {
            for_each = flatten([var.lifecycle_events])
            content {
              dynamic "pre_stop" {
                for_each = lifecycle.value.pre_stop != null ? [lifecycle.value.pre_stop] : []

                content {
                  dynamic "http_get" {
                    for_each = pre_stop.value.http_get != null ? [pre_stop.value.http_get] : []

                    content {
                      path   = http_get.value.path
                      port   = http_get.value.port
                      scheme = http_get.value.scheme
                      host   = http_get.value.host

                      dynamic "http_header" {
                        for_each = http_get.value.http_header != null ? http_get.value.http_header : []
                        content {
                          name  = http_header.value.name
                          value = http_header.value.value
                        }
                      }
                    }
                  }

                  dynamic "exec" {
                    for_each = pre_stop.value.exec != null ? [pre_stop.value.exec] : []

                    content {
                      command = exec.value.command
                    }
                  }

                  dynamic "tcp_socket" {
                    for_each = pre_stop.value.tcp_socket != null ? [pre_stop.value.tcp_socket] : []
                    content {
                      port = tcp_socket.value.port
                    }
                  }
                }
              }

              dynamic "post_start" {
                for_each = lifecycle.value.post_start != null ? [lifecycle.value.post_start] : []

                content {
                  dynamic "http_get" {
                    for_each = post_start.value.http_get != null ? [post_start.value.http_get] : []

                    content {
                      path   = http_get.value.path
                      port   = http_get.value.port
                      scheme = http_get.value.scheme
                      host   = http_get.value.host

                      dynamic "http_header" {
                        for_each = http_get.value.http_header != null ? http_get.value.http_header : []
                        content {
                          name  = http_header.value.name
                          value = http_header.value.value
                        }
                      }
                    }
                  }

                  dynamic "exec" {
                    for_each = post_start.value.exec != null ? [post_start.value.exec] : []

                    content {
                      command = exec.value.command
                    }
                  }

                  dynamic "tcp_socket" {
                    for_each = post_start.value.tcp_socket != null ? [post_start.value.tcp_socket] : []
                    content {
                      port = tcp_socket.value.port
                    }
                  }
                }
              }

            }
          }

          tty = var.tty
        }
      }
    }
  }
}