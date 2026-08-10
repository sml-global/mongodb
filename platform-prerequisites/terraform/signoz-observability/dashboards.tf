# Dashboards defined as code via the SigNoz Terraform provider's v2
# (Perses-based) signoz_dashboard schema. Migrated from the old
# jsonencode(layout)/jsonencode(widgets) v1 shape after upgrading SigNoz to
# v0.136.1 (which retires the v1 dashboard API -- see #123). Generated with
# `terraform plan -generate-config-out` against the live, already-migrated
# dashboards (import by ID, no dashboard recreated) per the provider's own
# migration guide (SigNoz/terraform-provider-signoz docs/guides/v0.0.x-to-v0.1.0.md).
# __generated__ by Terraform from "019fea62-9d30-7246-b95f-c4f6f767b919"
resource "signoz_dashboard" "k8s_pod_metrics" {
  name           = "kubernetes-pod-metrics-overall-1je68nfy"
  schema_version = "v6"
  spec = {
    display = {
      name = "Kubernetes Pod Metrics - Overall"
    }
    layouts = [
      {
        grid = {
          kind = "Grid"
          spec = {
            items = [
              {
                content = {
                  ref = "#/spec/panels/e16d581d-1da9-49ff-9c3b-1bb51c2f7730"
                }
                height = 7
                width  = 6
                x      = 0
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/18c1653b-f826-460d-9302-90bc6d3f5e52"
                }
                height = 7
                width  = 6
                x      = 6
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/a2cd4e4a-0b81-4a85-937f-48ca5c9f183b"
                }
                height = 7
                width  = 6
                x      = 0
                y      = 7
              },
              {
                content = {
                  ref = "#/spec/panels/1406e6b6-0c99-46d4-9782-530f6e7e053a"
                }
                height = 7
                width  = 6
                x      = 6
                y      = 7
              },
            ]
          }
        }
      },
    ]
    links = [
    ]
    panels = {
      "1406e6b6-0c99-46d4-9782-530f6e7e053a" = {
        kind = "Panel"
        spec = {
          display = {
            name = "Pod filesystem usage"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "percentunit"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                plugin = {
                  composite_query = {
                    kind = "signoz/CompositeQuery"
                    spec = {
                      queries = [
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "k8s.pod.filesystem.available"
                                    reduce_to         = "sum"
                                    space_aggregation = "sum"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = true
                                filter = {
                                  expression = "(k8s.cluster.name IN $k8s.cluster.name  AND k8s.node.name IN $k8s.node.name AND k8s.namespace.name IN $k8s.namespace.name)"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "k8s.node.name"
                                  },
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "k8s.namespace.name"
                                  },
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "k8s.pod.name"
                                  },
                                ]
                                having = {
                                }
                                name = "A"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "k8s.pod.filesystem.capacity"
                                    reduce_to         = "sum"
                                    space_aggregation = "sum"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = true
                                filter = {
                                  expression = "(k8s.cluster.name IN $k8s.cluster.name  AND k8s.node.name IN $k8s.node.name AND k8s.namespace.name IN $k8s.namespace.name)"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "k8s.node.name"
                                  },
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "k8s.namespace.name"
                                  },
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "k8s.pod.name"
                                  },
                                ]
                                having = {
                                }
                                name = "B"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_formula = {
                            spec = {
                              disabled   = false
                              expression = "(B-A)/B"
                              having = {
                              }
                              legend = "{{k8s.node.name}}-{{k8s.namespace.name}}-{{k8s.pod.name}}"
                              name   = "F1"
                            }
                            type = "builder_formula"
                          }
                        },
                      ]
                    }
                  }
                }
              }
            },
          ]
        }
      }
      "18c1653b-f826-460d-9302-90bc6d3f5e52" = {
        kind = "Panel"
        spec = {
          display = {
            name = "Pod memory usage (WSS)"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "bytes"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "k8s.pod.memory.working_set"
                            reduce_to         = "sum"
                            space_aggregation = "sum"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "(k8s.cluster.name IN $k8s.cluster.name  AND k8s.node.name IN $k8s.node.name AND k8s.namespace.name IN $k8s.namespace.name)"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "k8s.node.name"
                          },
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "k8s.namespace.name"
                          },
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "k8s.pod.name"
                          },
                        ]
                        having = {
                        }
                        legend = "{{k8s.namespace.name}}-{{k8s.pod.name}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      a2cd4e4a-0b81-4a85-937f-48ca5c9f183b = {
        kind = "Panel"
        spec = {
          display = {
            name = "Pod network IO"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "bytes"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "k8s.pod.network.io"
                            reduce_to         = "sum"
                            space_aggregation = "sum"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "(k8s.cluster.name IN $k8s.cluster.name  AND k8s.node.name IN $k8s.node.name AND k8s.namespace.name IN $k8s.namespace.name)"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "interface"
                          },
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "direction"
                          },
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "k8s.node.name"
                          },
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "k8s.namespace.name"
                          },
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "k8s.pod.name"
                          },
                        ]
                        having = {
                        }
                        legend = "{{k8s.namespace.name}}-{{k8s.pod.name}}-{{interface}}-{{direction}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      e16d581d-1da9-49ff-9c3b-1bb51c2f7730 = {
        kind = "Panel"
        spec = {
          display = {
            name = "Pod CPU usage"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "k8s.pod.cpu.time"
                            reduce_to         = "sum"
                            space_aggregation = "sum"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "(k8s.cluster.name IN $k8s.cluster.name  AND k8s.node.name IN $k8s.node.name AND k8s.namespace.name IN $k8s.namespace.name)"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "k8s.node.name"
                          },
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "k8s.pod.name"
                          },
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "k8s.namespace.name"
                          },
                        ]
                        having = {
                        }
                        legend = "{{k8s.namespace.name}}-{{k8s.pod.name}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
    }
    variables = [
      {
        list_variable = {
          kind = "ListVariable"
          spec = {
            allow_all_value = false
            allow_multiple  = false
            display = {
              description = "Name of the cluster"
              name        = "k8s.cluster.name"
            }
            name = "k8s.cluster.name"
            plugin = {
              dynamic_variable = {
                kind = "signoz/DynamicVariable"
                spec = {
                  name   = "k8s.cluster.name"
                  signal = "all"
                }
              }
            }
            sort = "none"
          }
        }
      },
      {
        list_variable = {
          kind = "ListVariable"
          spec = {
            allow_all_value = true
            allow_multiple  = true
            display = {
              description = "The k8s node name."
              name        = "k8s.node.name"
            }
            name = "k8s.node.name"
            plugin = {
              dynamic_variable = {
                kind = "signoz/DynamicVariable"
                spec = {
                  name   = "k8s.node.name"
                  signal = "all"
                }
              }
            }
            sort = "alphabetical-asc"
          }
        }
      },
      {
        list_variable = {
          kind = "ListVariable"
          spec = {
            allow_all_value = false
            allow_multiple  = false
            display = {
              description = "The k8s namespace name"
              name        = "k8s.namespace.name"
            }
            name = "k8s.namespace.name"
            plugin = {
              dynamic_variable = {
                kind = "signoz/DynamicVariable"
                spec = {
                  name   = "k8s.namespace.name"
                  signal = "all"
                }
              }
            }
            sort = "alphabetical-asc"
          }
        }
      },
    ]
  }
  tags = [
    {
      key   = "tag"
      value = "pod"
    },
    {
      key   = "tag"
      value = "k8s"
    },
  ]
}

# __generated__ by Terraform from "019fea62-9d23-7d38-b684-a57d9a5c06f8"
resource "signoz_dashboard" "k8s_node_metrics" {
  name           = "kubernetes-node-metrics-overall-t3aef22g"
  schema_version = "v6"
  spec = {
    display = {
      name = "Kubernetes Node Metrics - Overall"
    }
    layouts = [
      {
        grid = {
          kind = "Grid"
          spec = {
            items = [
              {
                content = {
                  ref = "#/spec/panels/e16d581d-1da9-49ff-9c3b-1bb51c2f7730"
                }
                height = 7
                width  = 6
                x      = 0
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/18c1653b-f826-460d-9302-90bc6d3f5e52"
                }
                height = 7
                width  = 6
                x      = 6
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/a2cd4e4a-0b81-4a85-937f-48ca5c9f183b"
                }
                height = 7
                width  = 6
                x      = 0
                y      = 7
              },
              {
                content = {
                  ref = "#/spec/panels/1406e6b6-0c99-46d4-9782-530f6e7e053a"
                }
                height = 7
                width  = 6
                x      = 6
                y      = 7
              },
            ]
          }
        }
      },
    ]
    links = [
    ]
    panels = {
      "1406e6b6-0c99-46d4-9782-530f6e7e053a" = {
        kind = "Panel"
        spec = {
          display = {
            name = "Node filesystem usage"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "percentunit"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                plugin = {
                  composite_query = {
                    kind = "signoz/CompositeQuery"
                    spec = {
                      queries = [
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "k8s.node.filesystem.available"
                                    reduce_to         = "sum"
                                    space_aggregation = "sum"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = true
                                filter = {
                                  expression = "(k8s.cluster.name IN $k8s.cluster.name  AND k8s.node.name IN $k8s.node.name)"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "k8s.node.name"
                                  },
                                ]
                                having = {
                                }
                                name = "A"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "k8s.node.filesystem.capacity"
                                    reduce_to         = "sum"
                                    space_aggregation = "sum"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = true
                                filter = {
                                  expression = "(k8s.cluster.name IN $k8s.cluster.name  AND k8s.node.name IN $k8s.node.name)"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "k8s.node.name"
                                  },
                                ]
                                having = {
                                }
                                name = "B"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_formula = {
                            spec = {
                              disabled   = false
                              expression = "(B-A)/B"
                              having = {
                              }
                              legend = "{{k8s.node.name}}"
                              name   = "F1"
                            }
                            type = "builder_formula"
                          }
                        },
                      ]
                    }
                  }
                }
              }
            },
          ]
        }
      }
      "18c1653b-f826-460d-9302-90bc6d3f5e52" = {
        kind = "Panel"
        spec = {
          display = {
            name = "Node memory usage (WSS)"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "percentunit"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                plugin = {
                  composite_query = {
                    kind = "signoz/CompositeQuery"
                    spec = {
                      queries = [
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "k8s.node.memory.working_set"
                                    reduce_to         = "sum"
                                    space_aggregation = "sum"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = true
                                filter = {
                                  expression = "(k8s.cluster.name IN $k8s.cluster.name  AND k8s.node.name IN $k8s.node.name)"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "k8s.node.name"
                                  },
                                ]
                                having = {
                                }
                                name = "A"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "k8s.node.allocatable_memory"
                                    reduce_to         = "sum"
                                    space_aggregation = "sum"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = true
                                filter = {
                                  expression = "(k8s.cluster.name IN $k8s.cluster.name  AND k8s.node.name IN $k8s.node.name)"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "k8s.node.name"
                                  },
                                ]
                                having = {
                                }
                                name = "B"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_formula = {
                            spec = {
                              disabled   = false
                              expression = "A/B"
                              having = {
                              }
                              legend = "{{k8s.node.name}}"
                              name   = "F1"
                            }
                            type = "builder_formula"
                          }
                        },
                      ]
                    }
                  }
                }
              }
            },
          ]
        }
      }
      a2cd4e4a-0b81-4a85-937f-48ca5c9f183b = {
        kind = "Panel"
        spec = {
          display = {
            name = "Node network IO"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "bytes"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "k8s.node.network.io"
                            reduce_to         = "sum"
                            space_aggregation = "sum"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "(k8s.cluster.name IN $k8s.cluster.name  AND k8s.node.name IN $k8s.node.name)"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "interface"
                          },
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "direction"
                          },
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "k8s.node.name"
                          },
                        ]
                        having = {
                        }
                        legend = "{{k8s.node.name}}-{{interface}}-{{direction}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      e16d581d-1da9-49ff-9c3b-1bb51c2f7730 = {
        kind = "Panel"
        spec = {
          display = {
            name = "Node CPU usage"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "percentunit"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                plugin = {
                  composite_query = {
                    kind = "signoz/CompositeQuery"
                    spec = {
                      queries = [
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "k8s.node.cpu.time"
                                    reduce_to         = "sum"
                                    space_aggregation = "sum"
                                    time_aggregation  = "rate"
                                  },
                                ]
                                disabled = true
                                filter = {
                                  expression = "(k8s.cluster.name IN $k8s.cluster.name  AND k8s.node.name IN $k8s.node.name)"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "k8s.node.name"
                                  },
                                ]
                                having = {
                                }
                                legend = "{{k8s.node.name}}"
                                name   = "A"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "k8s.node.allocatable_cpu"
                                    reduce_to         = "sum"
                                    space_aggregation = "sum"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = true
                                filter = {
                                  expression = "(k8s.cluster.name IN $k8s.cluster.name  AND k8s.node.name IN $k8s.node.name)"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "k8s.node.name"
                                  },
                                ]
                                having = {
                                }
                                legend = "{{k8s.node.name}}"
                                name   = "B"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_formula = {
                            spec = {
                              disabled   = false
                              expression = "A/B"
                              having = {
                              }
                              legend = "{{k8s.node.name}}"
                              name   = "F1"
                            }
                            type = "builder_formula"
                          }
                        },
                      ]
                    }
                  }
                }
              }
            },
          ]
        }
      }
    }
    variables = [
      {
        list_variable = {
          kind = "ListVariable"
          spec = {
            allow_all_value = false
            allow_multiple  = false
            display = {
              description = "The k8s cluster name"
              name        = "k8s.cluster.name"
            }
            name = "k8s.cluster.name"
            plugin = {
              dynamic_variable = {
                kind = "signoz/DynamicVariable"
                spec = {
                  name   = "k8s.cluster.name"
                  signal = "all"
                }
              }
            }
            sort = "none"
          }
        }
      },
      {
        list_variable = {
          kind = "ListVariable"
          spec = {
            allow_all_value = true
            allow_multiple  = true
            display = {
              description = "The k8s node name"
              name        = "k8s.node.name"
            }
            name = "k8s.node.name"
            plugin = {
              dynamic_variable = {
                kind = "signoz/DynamicVariable"
                spec = {
                  name   = "k8s.node.name"
                  signal = "all"
                }
              }
            }
            sort = "none"
          }
        }
      },
    ]
  }
  tags = [
    {
      key   = "tag"
      value = "node"
    },
    {
      key   = "tag"
      value = "k8s"
    },
    {
      key   = "tag"
      value = "kubelet"
    },
  ]
}

# __generated__ by Terraform from "019fea62-9c71-7df1-9b4b-b1546d51f1cb"
resource "signoz_dashboard" "mongodb_overview" {
  name           = "mongo-overview-dyq1drfw"
  schema_version = "v6"
  spec = {
    display = {
      description = "This dashboard provides a high-level overview of your MongoDB. It includes read/write performance, most-used replicas, collection metrics etc..."
      name        = "Mongo overview"
    }
    layouts = [
      {
        grid = {
          kind = "Grid"
          spec = {
            items = [
              {
                content = {
                  ref = "#/spec/panels/db33b09a-4273-4b14-a63f-926bf32de2b5"
                }
                height = 5
                width  = 12
                x      = 0
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/4c07a7d2-893a-46c2-bcdb-a19b6efeac3a"
                }
                height = 5
                width  = 6
                x      = 0
                y      = 5
              },
              {
                content = {
                  ref = "#/spec/panels/f2b46fdc-29d2-4c82-b79e-371eebcaa14c"
                }
                height = 5
                width  = 6
                x      = 6
                y      = 5
              },
              {
                content = {
                  ref = "#/spec/panels/dcfb3829-c3f2-44bb-907d-8dc8a6dc4aab"
                }
                height = 5
                width  = 6
                x      = 0
                y      = 10
              },
              {
                content = {
                  ref = "#/spec/panels/bfc9e80b-02bf-4122-b3da-3dd943d35012"
                }
                height = 5
                width  = 6
                x      = 6
                y      = 10
              },
              {
                content = {
                  ref = "#/spec/panels/14504a3c-4a05-4d22-bab3-e22e94f51380"
                }
                height = 5
                width  = 6
                x      = 0
                y      = 15
              },
              {
                content = {
                  ref = "#/spec/panels/a5a64eec-1034-4aa6-8cb1-05673c4426c6"
                }
                height = 5
                width  = 6
                x      = 6
                y      = 15
              },
              {
                content = {
                  ref = "#/spec/panels/503af589-ef4d-4fe3-8934-c8f7eb480d9a"
                }
                height = 5
                width  = 6
                x      = 0
                y      = 20
              },
              {
                content = {
                  ref = "#/spec/panels/0c3d2b15-89be-4d62-a821-b26d93332ed3"
                }
                height = 5
                width  = 6
                x      = 6
                y      = 20
              },
              {
                content = {
                  ref = "#/spec/panels/2db9bbd2-081f-4d84-a72e-a3c58b7e27a6"
                }
                height = 5
                width  = 6
                x      = 0
                y      = 25
              },
            ]
          }
        }
      },
    ]
    links = [
    ]
    panels = {
      "0c3d2b15-89be-4d62-a821-b26d93332ed3" = {
        kind = "Panel"
        spec = {
          display = {
            name = "Network IO"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "bytes"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                plugin = {
                  composite_query = {
                    kind = "signoz/CompositeQuery"
                    spec = {
                      queries = [
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "mongodb.network.io.receive"
                                    reduce_to         = "sum"
                                    space_aggregation = "sum"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "host.name IN $host.name"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "host.name"
                                  },
                                ]
                                having = {
                                }
                                legend = "Bytes received :: {{host.name}}"
                                name   = "A"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "mongodb.network.io.transmit"
                                    reduce_to         = "sum"
                                    space_aggregation = "sum"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "host.name IN $host.name"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "host.name"
                                  },
                                ]
                                having = {
                                }
                                legend = "Bytes transmitted :: {{host.name}}"
                                name   = "B"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                      ]
                    }
                  }
                }
              }
            },
          ]
        }
      }
      "14504a3c-4a05-4d22-bab3-e22e94f51380" = {
        kind = "Panel"
        spec = {
          display = {
            name = "Read latency"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "µs"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "mongodb.operation.latency.time"
                            reduce_to         = "sum"
                            space_aggregation = "max"
                            time_aggregation  = "max"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "(operation = 'read' AND host.name IN $host.name)"
                        }
                        group_by = [
                        ]
                        having = {
                        }
                        legend = "Latency"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      "2db9bbd2-081f-4d84-a72e-a3c58b7e27a6" = {
        kind = "Panel"
        spec = {
          display = {
            description = "Total number of operations"
            name        = "Global lock time"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "ms"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "mongodb.global_lock.time"
                            reduce_to         = "sum"
                            space_aggregation = "sum"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "host.name IN $host.name"
                        }
                        functions = [
                        ]
                        group_by = [
                        ]
                        having = {
                        }
                        legend = "lock time"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      "4c07a7d2-893a-46c2-bcdb-a19b6efeac3a" = {
        kind = "Panel"
        spec = {
          display = {
            description = "Total number of operations"
            name        = "Operations count"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "mongodb.operation.count"
                            reduce_to         = "sum"
                            space_aggregation = "sum"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "host.name IN $host.name"
                        }
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "operation"
                          },
                        ]
                        having = {
                        }
                        legend = "{{operation}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      "503af589-ef4d-4fe3-8934-c8f7eb480d9a" = {
        kind = "Panel"
        spec = {
          display = {
            name = "Command latency"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "µs"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "mongodb.operation.latency.time"
                            reduce_to         = "sum"
                            space_aggregation = "max"
                            time_aggregation  = "max"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "(host.name IN $host.name AND operation = 'command')"
                        }
                        group_by = [
                        ]
                        having = {
                        }
                        legend = "Latency"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      a5a64eec-1034-4aa6-8cb1-05673c4426c6 = {
        kind = "Panel"
        spec = {
          display = {
            name = "Write latency"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "µs"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "mongodb.operation.latency.time"
                            reduce_to         = "sum"
                            space_aggregation = "max"
                            time_aggregation  = "max"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "(host.name IN $host.name AND operation = 'write')"
                        }
                        group_by = [
                        ]
                        having = {
                        }
                        legend = "Latency"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      bfc9e80b-02bf-4122-b3da-3dd943d35012 = {
        kind = "Panel"
        spec = {
          display = {
            description = "The total time spent performing operations."
            name        = "Total operations time"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "ms"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "mongodb.operation.time"
                            reduce_to         = "sum"
                            space_aggregation = "sum"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "host.name IN $host.name"
                        }
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "operation"
                          },
                        ]
                        having = {
                        }
                        legend = "{{operation}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      db33b09a-4273-4b14-a63f-926bf32de2b5 = {
        kind = "Panel"
        spec = {
          display = {
            description = "Total number of collections for each database"
            name        = "DB Overview"
          }
          links = [
          ]
          plugin = {
            table_panel = {
              kind = "signoz/TablePanel"
              spec = {
                formatting = {
                  column_units = {
                    A = "short"
                    B = "short"
                    C = "short"
                    D = "bytes"
                    E = "short"
                    F = "short"
                    G = "bytes"
                    H = "bytes"
                  }
                  decimal_precision = "2"
                }
                visualization = {
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "scalar"
              spec = {
                plugin = {
                  composite_query = {
                    kind = "signoz/CompositeQuery"
                    spec = {
                      queries = [
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "mongodb.collection.count"
                                    reduce_to         = "last"
                                    space_aggregation = "sum"
                                    time_aggregation  = "max"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "host.name IN $host.name"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "database"
                                  },
                                ]
                                having = {
                                }
                                legend = "collections"
                                name   = "A"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "mongodb.connection.count"
                                    reduce_to         = "last"
                                    space_aggregation = "sum"
                                    time_aggregation  = "latest"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "(host.name IN $host.name AND type = 'active')"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "database"
                                  },
                                ]
                                having = {
                                }
                                legend = "active conns"
                                name   = "B"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "mongodb.connection.count"
                                    reduce_to         = "last"
                                    space_aggregation = "sum"
                                    time_aggregation  = "latest"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "(host.name IN $host.name AND type = 'current')"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "database"
                                  },
                                ]
                                having = {
                                }
                                legend = "current conns"
                                name   = "C"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "mongodb.index.size"
                                    reduce_to         = "last"
                                    space_aggregation = "sum"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "host.name IN $host.name"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "database"
                                  },
                                ]
                                having = {
                                }
                                legend = "index size"
                                name   = "D"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "mongodb.index.count"
                                    reduce_to         = "last"
                                    space_aggregation = "sum"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "host.name IN $host.name"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "database"
                                  },
                                ]
                                having = {
                                }
                                legend = "index count"
                                name   = "E"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "mongodb.object.count"
                                    reduce_to         = "last"
                                    space_aggregation = "sum"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "host.name IN $host.name"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "database"
                                  },
                                ]
                                having = {
                                }
                                legend = "objects count"
                                name   = "F"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "mongodb.memory.usage"
                                    reduce_to         = "avg"
                                    space_aggregation = "sum"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "(host.name IN $host.name AND type = 'resident')"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "database"
                                  },
                                ]
                                having = {
                                }
                                legend = "memory"
                                name   = "G"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "mongodb.data.size"
                                    reduce_to         = "avg"
                                    space_aggregation = "sum"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "host.name IN $host.name"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "database"
                                  },
                                ]
                                having = {
                                }
                                legend = "data size"
                                name   = "H"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                      ]
                    }
                  }
                }
              }
            },
          ]
        }
      }
      dcfb3829-c3f2-44bb-907d-8dc8a6dc4aab = {
        kind = "Panel"
        spec = {
          display = {
            description = "The number of cache operations"
            name        = "Cache operations"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "mongodb.cache.operations"
                            reduce_to         = "avg"
                            space_aggregation = "sum"
                            time_aggregation  = "increase"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "host.name IN $host.name"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "type"
                          },
                        ]
                        having = {
                        }
                        legend = "{{type}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      f2b46fdc-29d2-4c82-b79e-371eebcaa14c = {
        kind = "Panel"
        spec = {
          display = {
            description = "The number of open cursors maintained for clients.\n"
            name        = "Cursor count"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "mongodb.cursor.count"
                            reduce_to         = "sum"
                            space_aggregation = "sum"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "host.name IN $host.name"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "host.name"
                          },
                        ]
                        having = {
                        }
                        legend = "Cursor :: {{host.name}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
    }
    variables = [
      {
        list_variable = {
          kind = "ListVariable"
          spec = {
            allow_all_value = true
            allow_multiple  = true
            default_value   = jsonencode(["default"])
            display = {
              description = "List of hosts sending mongo metrics"
              name        = "host.name"
            }
            name = "host.name"
            plugin = {
              query_variable = {
                kind = "signoz/QueryVariable"
                spec = {
                  query_value = "SELECT JSONExtractString(labels, 'host.name') AS `host.name`\nFROM signoz_metrics.distributed_time_series_v4_1day\nWHERE metric_name = 'mongodb.memory.usage'\nGROUP BY `host.name`"
                }
              }
            }
            sort = "alphabetical-asc"
          }
        }
      },
    ]
  }
  tags = [
    {
      key   = "tag"
      value = "mongo"
    },
    {
      key   = "tag"
      value = "database"
    },
  ]
}

# __generated__ by Terraform from "019fea62-9cc6-7236-80db-3d6b40a4b6e6"
resource "signoz_dashboard" "postgres_overview" {
  name           = "aws-rds-postgres-ri0esvb5"
  schema_version = "v6"
  spec = {
    display = {
      name = "AWS RDS Postgres"
    }
    layouts = [
      {
        grid = {
          kind = "Grid"
          spec = {
            items = [
              {
                content = {
                  ref = "#/spec/panels/8d22c6a7-b22e-4ad2-b242-e15de32ddc0f"
                }
                height = 5
                width  = 6
                x      = 0
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/94fe032e-3ffc-4cdc-aae6-f851fa47d957"
                }
                height = 5
                width  = 6
                x      = 6
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/d73f2e63-33d8-40f7-a67b-861a628ba249"
                }
                height = 5
                width  = 6
                x      = 0
                y      = 5
              },
              {
                content = {
                  ref = "#/spec/panels/336bca83-50be-4937-b41b-ca8fde150f4d"
                }
                height = 5
                width  = 6
                x      = 6
                y      = 5
              },
              {
                content = {
                  ref = "#/spec/panels/6807e631-4894-4de8-8a55-686c8fa08d4b"
                }
                height = 5
                width  = 6
                x      = 0
                y      = 10
              },
              {
                content = {
                  ref = "#/spec/panels/d599a942-4dbf-4e29-a3ac-a3142399b557"
                }
                height = 5
                width  = 6
                x      = 6
                y      = 10
              },
              {
                content = {
                  ref = "#/spec/panels/31c78945-ea1e-4ae1-b0fb-6f1c9de2c016"
                }
                height = 5
                width  = 6
                x      = 0
                y      = 15
              },
              {
                content = {
                  ref = "#/spec/panels/845ee717-bbd1-424c-8293-f49e76aa43b3"
                }
                height = 5
                width  = 6
                x      = 6
                y      = 15
              },
              {
                content = {
                  ref = "#/spec/panels/c5189b72-1055-4d6a-b18d-fa23bd9c28d6"
                }
                height = 5
                width  = 6
                x      = 0
                y      = 20
              },
              {
                content = {
                  ref = "#/spec/panels/ae099f6e-5d6c-4127-ac70-2da9741837d7"
                }
                height = 5
                width  = 6
                x      = 6
                y      = 20
              },
              {
                content = {
                  ref = "#/spec/panels/03c1f0bd-6713-4355-b8e3-6ef781af32c2"
                }
                height = 5
                width  = 4
                x      = 0
                y      = 25
              },
              {
                content = {
                  ref = "#/spec/panels/37aabb43-fd8b-47c5-9444-0cd77f9ac435"
                }
                height = 5
                width  = 4
                x      = 4
                y      = 25
              },
              {
                content = {
                  ref = "#/spec/panels/c6939628-3c4c-48fb-a2cf-46f6cb358359"
                }
                height = 5
                width  = 4
                x      = 8
                y      = 25
              },
              {
                content = {
                  ref = "#/spec/panels/7854afc7-0cd5-4792-a760-be98a2e2f96b"
                }
                height = 5
                width  = 4
                x      = 0
                y      = 30
              },
              {
                content = {
                  ref = "#/spec/panels/8126584b-eaa9-4b79-ba8e-a00c394544d8"
                }
                height = 5
                width  = 4
                x      = 4
                y      = 30
              },
              {
                content = {
                  ref = "#/spec/panels/3d0a6717-1fd0-4810-b0e9-fe5190d5809f"
                }
                height = 5
                width  = 4
                x      = 8
                y      = 30
              },
              {
                content = {
                  ref = "#/spec/panels/ffc39591-288f-4b28-87ee-43456d5d0667"
                }
                height = 5
                width  = 6
                x      = 0
                y      = 35
              },
            ]
          }
        }
      },
    ]
    links = [
    ]
    panels = {
      "03c1f0bd-6713-4355-b8e3-6ef781af32c2" = {
        kind = "Panel"
        spec = {
          display = {
            name = "ReadThroughput"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "decbytes"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "aws_rds_read_throughput_average"
                            reduce_to         = "avg"
                            space_aggregation = "avg"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "dbinstance_identifier IN $dbinstance_identifier"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "dbinstance_identifier"
                          },
                        ]
                        having = {
                        }
                        legend = "{{dbinstance_identifier}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      "31c78945-ea1e-4ae1-b0fb-6f1c9de2c016" = {
        kind = "Panel"
        spec = {
          display = {
            description = "The percentage of I/O credits remaining in the burst bucket of your RDS database."
            name        = "EBSIOBalance%"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "aws_rds_ebsiobalance__average"
                            reduce_to         = "avg"
                            space_aggregation = "sum"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "dbinstance_identifier IN $dbinstance_identifier"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "dbinstance_identifier"
                          },
                        ]
                        having = {
                        }
                        legend = "{{dbinstance_identifier}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      "336bca83-50be-4937-b41b-ca8fde150f4d" = {
        kind = "Panel"
        spec = {
          display = {
            name = "CheckpointLag"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "aws_rds_checkpoint_lag_average"
                            reduce_to         = "avg"
                            space_aggregation = "sum"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "dbinstance_identifier IN $dbinstance_identifier"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "dbinstance_identifier"
                          },
                        ]
                        having = {
                        }
                        legend = "{{dbinstance_identifier}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      "37aabb43-fd8b-47c5-9444-0cd77f9ac435" = {
        kind = "Panel"
        spec = {
          display = {
            name = "ReadIOPS"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "aws_rds_read_iops_average"
                            reduce_to         = "avg"
                            space_aggregation = "avg"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "dbinstance_identifier IN $dbinstance_identifier"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "dbinstance_identifier"
                          },
                        ]
                        having = {
                        }
                        legend = "{{dbinstance_identifier}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      "3d0a6717-1fd0-4810-b0e9-fe5190d5809f" = {
        kind = "Panel"
        spec = {
          display = {
            name = "WriteLatency"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "aws_rds_write_latency_average"
                            reduce_to         = "avg"
                            space_aggregation = "sum"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "dbinstance_identifier IN $dbinstance_identifier"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "dbinstance_identifier"
                          },
                        ]
                        having = {
                        }
                        legend = "{{dbinstance_identifier}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      "6807e631-4894-4de8-8a55-686c8fa08d4b" = {
        kind = "Panel"
        spec = {
          display = {
            description = "The amount of available storage space."
            name        = "FreeStorageSpace"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "decbytes"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "aws_rds_free_storage_space_average"
                            reduce_to         = "avg"
                            space_aggregation = "sum"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "dbinstance_identifier IN $dbinstance_identifier"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "dbinstance_identifier"
                          },
                        ]
                        having = {
                        }
                        legend = "{{dbinstance_identifier}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      "7854afc7-0cd5-4792-a760-be98a2e2f96b" = {
        kind = "Panel"
        spec = {
          display = {
            name = "WriteThroughput"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "decbytes"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "aws_rds_write_throughput_average"
                            reduce_to         = "avg"
                            space_aggregation = "sum"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "dbinstance_identifier IN $dbinstance_identifier"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "dbinstance_identifier"
                          },
                        ]
                        having = {
                        }
                        legend = "{{dbinstance_identifier}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      "8126584b-eaa9-4b79-ba8e-a00c394544d8" = {
        kind = "Panel"
        spec = {
          display = {
            name = "WriteIOPS"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "aws_rds_write_iops_average"
                            reduce_to         = "avg"
                            space_aggregation = "sum"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "dbinstance_identifier IN $dbinstance_identifier"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "dbinstance_identifier"
                          },
                        ]
                        having = {
                        }
                        legend = "{{dbinstance_identifier}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      "845ee717-bbd1-424c-8293-f49e76aa43b3" = {
        kind = "Panel"
        spec = {
          display = {
            description = "The number of outstanding I/Os (read/write requests) waiting to access the disk."
            name        = "DiskQueueDepth"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "aws_rds_disk_queue_depth_average"
                            reduce_to         = "avg"
                            space_aggregation = "avg"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "dbinstance_identifier IN $dbinstance_identifier"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "dbinstance_identifier"
                          },
                        ]
                        having = {
                        }
                        legend = "{{dbinstance_identifier}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      "8d22c6a7-b22e-4ad2-b242-e15de32ddc0f" = {
        kind = "Panel"
        spec = {
          display = {
            description = "The percentage of CPU utilization."
            name        = "CPUUtilization"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "percent"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "aws_rds_cpuutilization_average"
                            reduce_to         = "avg"
                            space_aggregation = "sum"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "dbinstance_identifier IN $dbinstance_identifier"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "dbinstance_identifier"
                          },
                        ]
                        having = {
                        }
                        legend = "{{dbinstance_identifier}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      "94fe032e-3ffc-4cdc-aae6-f851fa47d957" = {
        kind = "Panel"
        spec = {
          display = {
            description = "The number of client network connections to the database instance."
            name        = "DatabaseConnections"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "short"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "aws_rds_database_connections_average"
                            reduce_to         = "avg"
                            space_aggregation = "sum"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "dbinstance_identifier IN $dbinstance_identifier"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "dbinstance_identifier"
                          },
                        ]
                        having = {
                        }
                        legend = "{{dbinstance_identifier}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      ae099f6e-5d6c-4127-ac70-2da9741837d7 = {
        kind = "Panel"
        spec = {
          display = {
            description = "The percentage of throughput credits remaining in the burst bucket of your RDS database. "
            name        = "EBSByteBalance%"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "aws_rds_ebsiobalance__average"
                            reduce_to         = "avg"
                            space_aggregation = "avg"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "dbinstance_identifier IN $dbinstance_identifier"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "dbinstance_identifier"
                          },
                        ]
                        having = {
                        }
                        legend = "{{dbinstance_identifier}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      c5189b72-1055-4d6a-b18d-fa23bd9c28d6 = {
        kind = "Panel"
        spec = {
          display = {
            name = "SwapUsage"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "decbytes"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "aws_rds_swap_usage_average"
                            reduce_to         = "avg"
                            space_aggregation = "avg"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "dbinstance_identifier IN $dbinstance_identifier"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "dbinstance_identifier"
                          },
                        ]
                        having = {
                        }
                        legend = "{{dbinstance_identifier}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      c6939628-3c4c-48fb-a2cf-46f6cb358359 = {
        kind = "Panel"
        spec = {
          display = {
            name = "ReadLatency"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "aws_rds_read_latency_average"
                            reduce_to         = "avg"
                            space_aggregation = "sum"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "dbinstance_identifier IN $dbinstance_identifier"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "dbinstance_identifier"
                          },
                        ]
                        having = {
                        }
                        legend = "{{dbinstance_identifier}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      d599a942-4dbf-4e29-a3ac-a3142399b557 = {
        kind = "Panel"
        spec = {
          display = {
            description = "The amount of available random access memory. This metric reports the value of the MemAvailable field of /proc/meminfo"
            name        = "FreeableMemory"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "decbytes"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "aws_rds_freeable_memory_average"
                            reduce_to         = "avg"
                            space_aggregation = "sum"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "dbinstance_identifier IN $dbinstance_identifier"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "dbinstance_identifier"
                          },
                        ]
                        having = {
                        }
                        legend = "{{dbinstance_identifier}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      d73f2e63-33d8-40f7-a67b-861a628ba249 = {
        kind = "Panel"
        spec = {
          display = {
            name = "ReplicaLag"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                  soft_max     = 0
                  soft_min     = 0
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "aws_rds_replica_lag_average"
                            reduce_to         = "avg"
                            space_aggregation = "sum"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "dbinstance_identifier IN $dbinstance_identifier"
                        }
                        functions = [
                        ]
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "dbinstance_identifier"
                          },
                        ]
                        having = {
                        }
                        legend = "{{dbinstance_identifier}}"
                        name   = "A"
                        order = [
                        ]
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      ffc39591-288f-4b28-87ee-43456d5d0667 = {
        kind = "Panel"
        spec = {
          display = {
            name = "Network transmit/receive"
          }
          links = [
          ]
          plugin = {
            table_panel = {
              kind = "signoz/TablePanel"
              spec = {
                formatting = {
                  decimal_precision = "2"
                }
                visualization = {
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "scalar"
              spec = {
                plugin = {
                  composite_query = {
                    kind = "signoz/CompositeQuery"
                    spec = {
                      queries = [
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "aws_rds_network_transmit_throughput_average"
                                    reduce_to         = "sum"
                                    space_aggregation = "sum"
                                    time_aggregation  = "sum"
                                  },
                                ]
                                disabled = true
                                filter = {
                                  expression = "dbinstance_identifier IN $dbinstance_identifier"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "dbinstance_identifier"
                                  },
                                ]
                                having = {
                                }
                                legend = "n/w transmit"
                                name   = "A"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "aws_rds_network_receive_throughput_average"
                                    reduce_to         = "sum"
                                    space_aggregation = "sum"
                                    time_aggregation  = "sum"
                                  },
                                ]
                                disabled = true
                                filter = {
                                  expression = "dbinstance_identifier IN $dbinstance_identifier"
                                }
                                functions = [
                                ]
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "dbinstance_identifier"
                                  },
                                ]
                                having = {
                                }
                                legend = "n/w receive"
                                name   = "B"
                                order = [
                                ]
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_formula = {
                            spec = {
                              disabled   = false
                              expression = "A/1024/1024"
                              having = {
                              }
                              legend = "n/w transmit (mb)"
                              name   = "F1"
                            }
                            type = "builder_formula"
                          }
                        },
                        {
                          builder_formula = {
                            spec = {
                              disabled   = false
                              expression = "B/1024/1024"
                              having = {
                              }
                              legend = "n/w receive (mb)"
                              name   = "F2"
                            }
                            type = "builder_formula"
                          }
                        },
                      ]
                    }
                  }
                }
              }
            },
          ]
        }
      }
    }
    variables = [
      {
        list_variable = {
          kind = "ListVariable"
          spec = {
            allow_all_value = true
            allow_multiple  = true
            default_value   = jsonencode(["integration-db-instance-instance-1", "integration-db-instance-instance-2", "integration-db-instance-instance-3", "integration-test-postgres-instance-1", "integration-test-postgres-instance-2", "integration-test-postgres-instance-3", "integration-testing-db-instance-1", "integration-testing-db-instance-2", "integration-testing-db-instance-3"])
            display = {
              description = "This is the unique key that identifies a DB instance"
              name        = "dbinstance_identifier"
            }
            name = "dbinstance_identifier"
            plugin = {
              query_variable = {
                kind = "signoz/QueryVariable"
                spec = {
                  query_value = "SELECT JSONExtractString(labels, 'dbinstance_identifier') as dbinstance_identifier\nFROM signoz_metrics.distributed_time_series_v4_1day\nWHERE metric_name like 'aws_rds_database_connections_average'\nGROUP BY dbinstance_identifier"
                }
              }
            }
            sort = "alphabetical-asc"
          }
        }
      },
    ]
  }
  tags = [
    {
      key   = "tag"
      value = "aws"
    },
    {
      key   = "tag"
      value = "rds"
    },
    {
      key   = "tag"
      value = "postgres"
    },
  ]
}

# __generated__ by Terraform from "019fea62-9d17-7793-91db-83951bd4e522"
resource "signoz_dashboard" "otel_collector_pipeline_health" {
  name           = "opentelemetry-collector-mjxvtvb8"
  schema_version = "v6"
  spec = {
    display = {
      description = "Pipeline health for the OTel Collector: receiver throughput, processor drops, exporter delivery, queue depth, and process resources."
      name        = "OpenTelemetry Collector"
    }
    layouts = [
      {
        grid = {
          kind = "Grid"
          spec = {
            display = {
              collapse = {
                open = true
              }
              title = "Overview"
            }
            items = [
              {
                content = {
                  ref = "#/spec/panels/v_recv_spans"
                }
                height = 3
                width  = 2
                x      = 0
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/v_recv_metrics"
                }
                height = 3
                width  = 2
                x      = 2
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/v_recv_logs"
                }
                height = 3
                width  = 2
                x      = 4
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/v_exp_spans"
                }
                height = 3
                width  = 2
                x      = 6
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/v_exp_metrics"
                }
                height = 3
                width  = 2
                x      = 8
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/v_exp_logs"
                }
                height = 3
                width  = 2
                x      = 10
                y      = 0
              },
            ]
          }
        }
      },
      {
        grid = {
          kind = "Grid"
          spec = {
            display = {
              collapse = {
                open = true
              }
              title = "Receivers"
            }
            items = [
              {
                content = {
                  ref = "#/spec/panels/g_recv_spans"
                }
                height = 7
                width  = 6
                x      = 0
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/g_recv_spans_refused"
                }
                height = 7
                width  = 6
                x      = 6
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/g_recv_metrics"
                }
                height = 7
                width  = 6
                x      = 0
                y      = 7
              },
              {
                content = {
                  ref = "#/spec/panels/g_recv_metrics_refused"
                }
                height = 7
                width  = 6
                x      = 6
                y      = 7
              },
              {
                content = {
                  ref = "#/spec/panels/g_recv_logs"
                }
                height = 7
                width  = 6
                x      = 0
                y      = 14
              },
              {
                content = {
                  ref = "#/spec/panels/g_recv_logs_refused"
                }
                height = 7
                width  = 6
                x      = 6
                y      = 14
              },
            ]
          }
        }
      },
      {
        grid = {
          kind = "Grid"
          spec = {
            display = {
              collapse = {
                open = true
              }
              title = "Processors"
            }
            items = [
              {
                content = {
                  ref = "#/spec/panels/g_proc_incoming"
                }
                height = 7
                width  = 6
                x      = 0
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/g_proc_outgoing"
                }
                height = 7
                width  = 6
                x      = 6
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/g_batch_size"
                }
                height = 7
                width  = 6
                x      = 0
                y      = 7
              },
              {
                content = {
                  ref = "#/spec/panels/g_batch_trigger"
                }
                height = 7
                width  = 6
                x      = 6
                y      = 7
              },
            ]
          }
        }
      },
      {
        grid = {
          kind = "Grid"
          spec = {
            display = {
              collapse = {
                open = true
              }
              title = "Exporters"
            }
            items = [
              {
                content = {
                  ref = "#/spec/panels/g_exp_spans"
                }
                height = 7
                width  = 6
                x      = 0
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/g_exp_spans_failed"
                }
                height = 7
                width  = 6
                x      = 6
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/g_exp_metrics"
                }
                height = 7
                width  = 6
                x      = 0
                y      = 7
              },
              {
                content = {
                  ref = "#/spec/panels/g_exp_metrics_failed"
                }
                height = 7
                width  = 6
                x      = 6
                y      = 7
              },
              {
                content = {
                  ref = "#/spec/panels/g_exp_logs"
                }
                height = 7
                width  = 6
                x      = 0
                y      = 14
              },
              {
                content = {
                  ref = "#/spec/panels/g_exp_logs_failed"
                }
                height = 7
                width  = 6
                x      = 6
                y      = 14
              },
              {
                content = {
                  ref = "#/spec/panels/g_exp_queue_size"
                }
                height = 7
                width  = 6
                x      = 0
                y      = 21
              },
              {
                content = {
                  ref = "#/spec/panels/g_exp_queue_util"
                }
                height = 7
                width  = 6
                x      = 6
                y      = 21
              },
              {
                content = {
                  ref = "#/spec/panels/g_exp_in_flight"
                }
                height = 7
                width  = 12
                x      = 0
                y      = 28
              },
            ]
          }
        }
      },
      {
        grid = {
          kind = "Grid"
          spec = {
            display = {
              collapse = {
                open = true
              }
              title = "Process Resources"
            }
            items = [
              {
                content = {
                  ref = "#/spec/panels/g_heap_mem"
                }
                height = 7
                width  = 6
                x      = 0
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/g_rss_mem"
                }
                height = 7
                width  = 6
                x      = 6
                y      = 0
              },
              {
                content = {
                  ref = "#/spec/panels/g_cpu"
                }
                height = 7
                width  = 6
                x      = 0
                y      = 7
              },
              {
                content = {
                  ref = "#/spec/panels/g_alloc_rate"
                }
                height = 7
                width  = 6
                x      = 6
                y      = 7
              },
            ]
          }
        }
      },
    ]
    links = [
    ]
    panels = {
      g_alloc_rate = {
        kind = "Panel"
        spec = {
          display = {
            description = "Heap allocation throughput in bytes per second, per collector instance. High rates drive GC pressure and CPU overhead."
            name        = "Memory Allocation Rate"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "bytes"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_process_runtime_total_alloc_bytes"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "resource"
                            field_data_type = "string"
                            name            = "service.instance.id"
                          },
                        ]
                        having = {
                        }
                        legend        = "instance: {{service.instance.id}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_batch_size = {
        kind = "Panel"
        spec = {
          display = {
            description = "Items per batch at p50, p95, and p99. A large gap between p50 and p99 points to bursty traffic."
            name        = "Batch Send Size (p50 / p95 / p99)"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                plugin = {
                  composite_query = {
                    kind = "signoz/CompositeQuery"
                    spec = {
                      queries = [
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "otelcol_processor_batch_batch_send_size.bucket"
                                    space_aggregation = "p50"
                                    temporality       = "cumulative"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "service.name IN $service_name"
                                }
                                having = {
                                }
                                legend        = "p50"
                                name          = "A"
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "otelcol_processor_batch_batch_send_size.bucket"
                                    space_aggregation = "p95"
                                    temporality       = "cumulative"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "service.name IN $service_name"
                                }
                                having = {
                                }
                                legend        = "p95"
                                name          = "B"
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "otelcol_processor_batch_batch_send_size.bucket"
                                    space_aggregation = "p99"
                                    temporality       = "cumulative"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "service.name IN $service_name"
                                }
                                having = {
                                }
                                legend        = "p99"
                                name          = "C"
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                      ]
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_batch_trigger = {
        kind = "Panel"
        spec = {
          display = {
            description = "Batches flushed by timeout per second, by processor. High rate with small batch sizes means the collector is under-loaded relative to the configured batch size."
            name        = "Batch Timeout Trigger Sends /s by Processor"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_processor_batch_timeout_trigger_send"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "processor"
                          },
                        ]
                        having = {
                        }
                        legend        = "{{processor}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_cpu = {
        kind = "Panel"
        spec = {
          display = {
            description = "CPU seconds consumed per second, per collector instance. Values near the number of available cores mean the collector is CPU-saturated."
            name        = "CPU Usage (user + system)"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_process_cpu_seconds"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "resource"
                            field_data_type = "string"
                            name            = "service.instance.id"
                          },
                        ]
                        having = {
                        }
                        legend        = "instance: {{service.instance.id}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_exp_in_flight = {
        kind = "Panel"
        spec = {
          display = {
            description = "Export requests currently active, including retries. High values with a slow-draining queue point to backend latency or connectivity issues."
            name        = "Exporter In-Flight Requests by Exporter"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_exporter_in_flight_requests"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "exporter"
                          },
                        ]
                        having = {
                        }
                        legend        = "{{exporter}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_exp_logs = {
        kind = "Panel"
        spec = {
          display = {
            description = "Log records delivered to the backend per second, by exporter."
            name        = "Log Records Sent /s by Exporter"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_exporter_sent_log_records"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "exporter"
                          },
                        ]
                        having = {
                        }
                        legend        = "{{exporter}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_exp_logs_failed = {
        kind = "Panel"
        spec = {
          display = {
            description = "Log records the exporter failed to deliver per second."
            name        = "Log Record Send Failures /s by Exporter"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                thresholds = [
                  {
                    color = "#f6be00"
                    unit  = "none"
                    value = 0
                  },
                ]
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_exporter_send_failed_log_records"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "exporter"
                          },
                        ]
                        having = {
                        }
                        legend        = "{{exporter}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_exp_metrics = {
        kind = "Panel"
        spec = {
          display = {
            description = "Metric points delivered to the backend per second, by exporter."
            name        = "Metric Points Sent /s by Exporter"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_exporter_sent_metric_points"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "exporter"
                          },
                        ]
                        having = {
                        }
                        legend        = "{{exporter}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_exp_metrics_failed = {
        kind = "Panel"
        spec = {
          display = {
            description = "Metric points the exporter failed to deliver per second."
            name        = "Metric Point Send Failures /s by Exporter"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                thresholds = [
                  {
                    color = "#f6be00"
                    unit  = "none"
                    value = 0
                  },
                ]
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_exporter_send_failed_metric_points"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "exporter"
                          },
                        ]
                        having = {
                        }
                        legend        = "{{exporter}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_exp_queue_size = {
        kind = "Panel"
        spec = {
          display = {
            description = "Queue depth vs. capacity per exporter. Size approaching capacity means the exporter can't keep up with incoming data."
            name        = "Exporter Queue Size vs Capacity"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                plugin = {
                  composite_query = {
                    kind = "signoz/CompositeQuery"
                    spec = {
                      queries = [
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "otelcol_exporter_queue_size"
                                    space_aggregation = "max"
                                    temporality       = "unspecified"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "service.name IN $service_name"
                                }
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "exporter"
                                  },
                                ]
                                having = {
                                }
                                legend        = "size: {{exporter}}"
                                name          = "A"
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "otelcol_exporter_queue_capacity"
                                    space_aggregation = "max"
                                    temporality       = "unspecified"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "service.name IN $service_name"
                                }
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "exporter"
                                  },
                                ]
                                having = {
                                }
                                legend        = "capacity: {{exporter}}"
                                name          = "B"
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                      ]
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_exp_queue_util = {
        kind = "Panel"
        spec = {
          display = {
            description = "Queue fill as a percentage per exporter. Above 80%, the exporter risks dropping data under sustained load."
            name        = "Exporter Queue Utilization %"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "percent"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                thresholds = [
                  {
                    color = "#e53935"
                    label = "Saturation"
                    unit  = "percent"
                    value = 80
                  },
                ]
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                plugin = {
                  composite_query = {
                    kind = "signoz/CompositeQuery"
                    spec = {
                      queries = [
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "otelcol_exporter_queue_size"
                                    space_aggregation = "max"
                                    temporality       = "unspecified"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = true
                                filter = {
                                  expression = "service.name IN $service_name"
                                }
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "exporter"
                                  },
                                ]
                                having = {
                                }
                                name          = "A"
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "otelcol_exporter_queue_capacity"
                                    space_aggregation = "max"
                                    temporality       = "unspecified"
                                    time_aggregation  = "avg"
                                  },
                                ]
                                disabled = true
                                filter = {
                                  expression = "service.name IN $service_name"
                                }
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "exporter"
                                  },
                                ]
                                having = {
                                }
                                name          = "B"
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_formula = {
                            spec = {
                              disabled   = false
                              expression = "A / B * 100"
                              having = {
                              }
                              legend = "{{exporter}}"
                              name   = "F1"
                            }
                            type = "builder_formula"
                          }
                        },
                      ]
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_exp_spans = {
        kind = "Panel"
        spec = {
          display = {
            description = "Spans delivered to the backend per second, by exporter."
            name        = "Spans Sent /s by Exporter"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_exporter_sent_spans"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "exporter"
                          },
                        ]
                        having = {
                        }
                        legend        = "{{exporter}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_exp_spans_failed = {
        kind = "Panel"
        spec = {
          display = {
            description = "Spans the exporter failed to deliver per second. Any non-zero value needs investigation."
            name        = "Span Send Failures /s by Exporter"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                thresholds = [
                  {
                    color = "#f6be00"
                    unit  = "none"
                    value = 0
                  },
                ]
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_exporter_send_failed_spans"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "exporter"
                          },
                        ]
                        having = {
                        }
                        legend        = "{{exporter}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_heap_mem = {
        kind = "Panel"
        spec = {
          display = {
            description = "Heap bytes held by live objects, per collector instance. Sustained growth between GC cycles points to a memory leak."
            name        = "Heap Memory Allocated"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "bytes"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_process_runtime_heap_alloc_bytes"
                            space_aggregation = "sum"
                            temporality       = "unspecified"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "resource"
                            field_data_type = "string"
                            name            = "service.instance.id"
                          },
                        ]
                        having = {
                        }
                        legend        = "instance: {{service.instance.id}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_proc_incoming = {
        kind = "Panel"
        spec = {
          display = {
            description = "Items entering each processor per second. Covers spans, metric points, and log records combined."
            name        = "Items Incoming /s by Processor"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_processor_incoming_items"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "processor"
                          },
                        ]
                        having = {
                        }
                        legend        = "{{processor}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_proc_outgoing = {
        kind = "Panel"
        spec = {
          display = {
            description = "Items leaving each processor per second. A rate below incoming means the processor dropped or filtered data."
            name        = "Items Outgoing /s by Processor"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_processor_outgoing_items"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "processor"
                          },
                        ]
                        having = {
                        }
                        legend        = "{{processor}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_recv_logs = {
        kind = "Panel"
        spec = {
          display = {
            description = "Log records entering the pipeline per second, by receiver."
            name        = "Accepted Log Records /s by Receiver"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_receiver_accepted_log_records"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "receiver"
                          },
                        ]
                        having = {
                        }
                        legend        = "{{receiver}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_recv_logs_refused = {
        kind = "Panel"
        spec = {
          display = {
            description = "Refused = pipeline back-pressure. Failed = internal receiver error. Both cause log record loss."
            name        = "Refused & Failed Log Records /s by Receiver"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                thresholds = [
                  {
                    color = "#f6be00"
                    unit  = "none"
                    value = 0
                  },
                ]
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                plugin = {
                  composite_query = {
                    kind = "signoz/CompositeQuery"
                    spec = {
                      queries = [
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "otelcol_receiver_refused_log_records"
                                    space_aggregation = "sum"
                                    temporality       = "cumulative"
                                    time_aggregation  = "rate"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "service.name IN $service_name"
                                }
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "receiver"
                                  },
                                ]
                                having = {
                                }
                                legend        = "refused: {{receiver}}"
                                name          = "A"
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "otelcol_receiver_failed_log_records"
                                    space_aggregation = "sum"
                                    temporality       = "cumulative"
                                    time_aggregation  = "rate"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "service.name IN $service_name"
                                }
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "receiver"
                                  },
                                ]
                                having = {
                                }
                                legend        = "failed: {{receiver}}"
                                name          = "B"
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                      ]
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_recv_metrics = {
        kind = "Panel"
        spec = {
          display = {
            description = "Metric points entering the pipeline per second, by receiver."
            name        = "Accepted Metric Points /s by Receiver"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_receiver_accepted_metric_points"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "receiver"
                          },
                        ]
                        having = {
                        }
                        legend        = "{{receiver}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_recv_metrics_refused = {
        kind = "Panel"
        spec = {
          display = {
            description = "Refused = pipeline back-pressure. Failed = internal receiver error. Both cause metric point loss."
            name        = "Refused & Failed Metric Points /s by Receiver"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                thresholds = [
                  {
                    color = "#f6be00"
                    unit  = "none"
                    value = 0
                  },
                ]
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                plugin = {
                  composite_query = {
                    kind = "signoz/CompositeQuery"
                    spec = {
                      queries = [
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "otelcol_receiver_refused_metric_points"
                                    space_aggregation = "sum"
                                    temporality       = "cumulative"
                                    time_aggregation  = "rate"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "service.name IN $service_name"
                                }
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "receiver"
                                  },
                                ]
                                having = {
                                }
                                legend        = "refused: {{receiver}}"
                                name          = "A"
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "otelcol_receiver_failed_metric_points"
                                    space_aggregation = "sum"
                                    temporality       = "cumulative"
                                    time_aggregation  = "rate"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "service.name IN $service_name"
                                }
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "receiver"
                                  },
                                ]
                                having = {
                                }
                                legend        = "failed: {{receiver}}"
                                name          = "B"
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                      ]
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_recv_spans = {
        kind = "Panel"
        spec = {
          display = {
            description = "Spans entering the pipeline per second, by receiver."
            name        = "Accepted Spans /s by Receiver"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_receiver_accepted_spans"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "attribute"
                            field_data_type = "string"
                            name            = "receiver"
                          },
                        ]
                        having = {
                        }
                        legend        = "{{receiver}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_recv_spans_refused = {
        kind = "Panel"
        spec = {
          display = {
            description = "Refused = pipeline back-pressure (downstream can't accept). Failed = internal receiver error. Both cause span loss."
            name        = "Refused & Failed Spans /s by Receiver"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                thresholds = [
                  {
                    color = "#f6be00"
                    unit  = "none"
                    value = 0
                  },
                ]
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                plugin = {
                  composite_query = {
                    kind = "signoz/CompositeQuery"
                    spec = {
                      queries = [
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "otelcol_receiver_refused_spans"
                                    space_aggregation = "sum"
                                    temporality       = "cumulative"
                                    time_aggregation  = "rate"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "service.name IN $service_name"
                                }
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "receiver"
                                  },
                                ]
                                having = {
                                }
                                legend        = "refused: {{receiver}}"
                                name          = "A"
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                        {
                          builder_query = {
                            spec = {
                              metrics = {
                                aggregations = [
                                  {
                                    metric_name       = "otelcol_receiver_failed_spans"
                                    space_aggregation = "sum"
                                    temporality       = "cumulative"
                                    time_aggregation  = "rate"
                                  },
                                ]
                                disabled = false
                                filter = {
                                  expression = "service.name IN $service_name"
                                }
                                group_by = [
                                  {
                                    field_context   = "attribute"
                                    field_data_type = "string"
                                    name            = "receiver"
                                  },
                                ]
                                having = {
                                }
                                legend        = "failed: {{receiver}}"
                                name          = "B"
                                signal        = "metrics"
                                step_interval = "60"
                              }
                            }
                            type = "builder_query"
                          }
                        },
                      ]
                    }
                  }
                }
              }
            },
          ]
        }
      }
      g_rss_mem = {
        kind = "Panel"
        spec = {
          display = {
            description = "Physical memory used by each collector instance, including Go runtime overhead."
            name        = "Process RSS Memory"
          }
          links = [
          ]
          plugin = {
            time_series_panel = {
              kind = "signoz/TimeSeriesPanel"
              spec = {
                axes = {
                  is_log_scale = false
                }
                chart_appearance = {
                  fill_mode          = "none"
                  line_interpolation = "spline"
                  line_style         = "solid"
                  show_points        = false
                  span_gaps = {
                    fill_only_below = false
                  }
                }
                formatting = {
                  decimal_precision = "2"
                  unit              = "bytes"
                }
                legend = {
                  mode     = "list"
                  position = "bottom"
                }
                visualization = {
                  fill_spans      = false
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "time_series"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_process_memory_rss"
                            space_aggregation = "sum"
                            temporality       = "unspecified"
                            time_aggregation  = "avg"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        group_by = [
                          {
                            field_context   = "resource"
                            field_data_type = "string"
                            name            = "service.instance.id"
                          },
                        ]
                        having = {
                        }
                        legend        = "instance: {{service.instance.id}}"
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      v_exp_logs = {
        kind = "Panel"
        spec = {
          display = {
            description = "Log records delivered to the backend per second, summed across all exporters."
            name        = "Log Records Sent /s"
          }
          links = [
          ]
          plugin = {
            number_panel = {
              kind = "signoz/NumberPanel"
              spec = {
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                visualization = {
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "scalar"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_exporter_sent_log_records"
                            reduce_to         = "sum"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        having = {
                        }
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      v_exp_metrics = {
        kind = "Panel"
        spec = {
          display = {
            description = "Metric points delivered to the backend per second, summed across all exporters."
            name        = "Metric Points Sent /s"
          }
          links = [
          ]
          plugin = {
            number_panel = {
              kind = "signoz/NumberPanel"
              spec = {
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                visualization = {
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "scalar"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_exporter_sent_metric_points"
                            reduce_to         = "sum"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        having = {
                        }
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      v_exp_spans = {
        kind = "Panel"
        spec = {
          display = {
            description = "Spans delivered to the backend per second, summed across all exporters."
            name        = "Spans Sent /s"
          }
          links = [
          ]
          plugin = {
            number_panel = {
              kind = "signoz/NumberPanel"
              spec = {
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                visualization = {
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "scalar"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_exporter_sent_spans"
                            reduce_to         = "sum"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        having = {
                        }
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      v_recv_logs = {
        kind = "Panel"
        spec = {
          display = {
            description = "Log records pushed into the pipeline per second, summed across all receivers."
            name        = "Log Records Received /s"
          }
          links = [
          ]
          plugin = {
            number_panel = {
              kind = "signoz/NumberPanel"
              spec = {
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                visualization = {
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "scalar"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_receiver_accepted_log_records"
                            reduce_to         = "sum"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        having = {
                        }
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      v_recv_metrics = {
        kind = "Panel"
        spec = {
          display = {
            description = "Metric points pushed into the pipeline per second, summed across all receivers."
            name        = "Metric Points Received /s"
          }
          links = [
          ]
          plugin = {
            number_panel = {
              kind = "signoz/NumberPanel"
              spec = {
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                visualization = {
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "scalar"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_receiver_accepted_metric_points"
                            reduce_to         = "sum"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        having = {
                        }
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
      v_recv_spans = {
        kind = "Panel"
        spec = {
          display = {
            description = "Spans pushed into the pipeline per second, summed across all receivers."
            name        = "Spans Received /s"
          }
          links = [
          ]
          plugin = {
            number_panel = {
              kind = "signoz/NumberPanel"
              spec = {
                formatting = {
                  decimal_precision = "2"
                  unit              = "none"
                }
                visualization = {
                  time_preference = "global_time"
                }
              }
            }
          }
          queries = [
            {
              kind = "scalar"
              spec = {
                name = "A"
                plugin = {
                  builder_query = {
                    kind = "signoz/BuilderQuery"
                    spec = {
                      metrics = {
                        aggregations = [
                          {
                            metric_name       = "otelcol_receiver_accepted_spans"
                            reduce_to         = "sum"
                            space_aggregation = "sum"
                            temporality       = "cumulative"
                            time_aggregation  = "rate"
                          },
                        ]
                        disabled = false
                        filter = {
                          expression = "service.name IN $service_name"
                        }
                        having = {
                        }
                        name          = "A"
                        signal        = "metrics"
                        step_interval = "60"
                      }
                    }
                  }
                }
              }
            },
          ]
        }
      }
    }
    variables = [
      {
        list_variable = {
          kind = "ListVariable"
          spec = {
            allow_all_value = true
            allow_multiple  = true
            display = {
              description = "Filter by collector service (service.name)."
              name        = "service_name"
            }
            name = "service_name"
            plugin = {
              dynamic_variable = {
                kind = "signoz/DynamicVariable"
                spec = {
                  name   = "service.name"
                  signal = "metrics"
                }
              }
            }
            sort = "alphabetical-asc"
          }
        }
      },
    ]
  }
  tags = [
    {
      key   = "tag"
      value = "opentelemetry"
    },
    {
      key   = "tag"
      value = "otel"
    },
    {
      key   = "tag"
      value = "collector"
    },
    {
      key   = "tag"
      value = "metrics"
    },
    {
      key   = "tag"
      value = "infrastructure"
    },
  ]
}
