defmodule Sprites.Shapes do
  @moduledoc """
  Centralized request/response shape validation using Zoi.

  Schemas are intentionally tolerant (`unrecognized_keys: :preserve`) so the
  client remains forward-compatible with additive API changes.
  """

  @type parse_error :: {:shape_error, atom(), [Zoi.Error.t()]}

  @sprite_url_settings_schema Zoi.map(
                                %{
                                  "auth" => Zoi.string() |> Zoi.optional()
                                },
                                unrecognized_keys: :preserve
                              )

  @sprite_schema Zoi.map(
                   %{
                     "id" => Zoi.string() |> Zoi.optional(),
                     "name" => Zoi.string() |> Zoi.optional(),
                     "organization" => Zoi.string() |> Zoi.optional(),
                     "status" => Zoi.string() |> Zoi.optional(),
                     "url" => Zoi.string() |> Zoi.optional(),
                     "url_settings" => @sprite_url_settings_schema |> Zoi.optional(),
                     "created_at" => Zoi.string() |> Zoi.optional(),
                     "updated_at" => Zoi.string() |> Zoi.optional(),
                     "last_started_at" => Zoi.string() |> Zoi.nullish() |> Zoi.optional(),
                     "last_active_at" => Zoi.string() |> Zoi.nullish() |> Zoi.optional(),
                     "config" => Zoi.any() |> Zoi.optional(),
                     "environment" => Zoi.any() |> Zoi.optional()
                   },
                   unrecognized_keys: :preserve
                 )

  @sprite_entry_schema Zoi.map(
                         %{
                           "name" => Zoi.string(),
                           "org_slug" => Zoi.string() |> Zoi.optional(),
                           "updated_at" => Zoi.string() |> Zoi.optional(),
                           "id" => Zoi.string() |> Zoi.optional(),
                           "status" => Zoi.string() |> Zoi.optional(),
                           "url" => Zoi.string() |> Zoi.optional(),
                           "created_at" => Zoi.string() |> Zoi.optional(),
                           "organization" => Zoi.string() |> Zoi.optional(),
                           "url_settings" => @sprite_url_settings_schema |> Zoi.optional()
                         },
                         unrecognized_keys: :preserve
                       )

  @sprite_page_schema Zoi.map(
                        %{
                          "sprites" => Zoi.array(@sprite_entry_schema),
                          "has_more" => Zoi.boolean() |> Zoi.optional(),
                          "next_continuation_token" =>
                            Zoi.string() |> Zoi.nullish() |> Zoi.optional()
                        },
                        unrecognized_keys: :preserve
                      )

  @session_schema Zoi.map(
                    %{
                      "id" => Zoi.union([Zoi.integer(), Zoi.string()]),
                      "command" => Zoi.string(),
                      "workdir" => Zoi.string() |> Zoi.nullish() |> Zoi.optional(),
                      "created" => Zoi.string() |> Zoi.nullish() |> Zoi.optional(),
                      "bytes_per_second" => Zoi.number() |> Zoi.optional(),
                      "is_active" => Zoi.boolean() |> Zoi.optional(),
                      "last_activity" => Zoi.string() |> Zoi.nullish() |> Zoi.optional(),
                      "tty" => Zoi.boolean() |> Zoi.optional(),
                      "owner" => Zoi.boolean() |> Zoi.optional()
                    },
                    unrecognized_keys: :preserve
                  )

  @checkpoint_schema Zoi.map(
                       %{
                         "id" => Zoi.string(),
                         "create_time" => Zoi.string() |> Zoi.nullish() |> Zoi.optional(),
                         "history" => Zoi.array(Zoi.string()) |> Zoi.optional(),
                         "comment" => Zoi.string() |> Zoi.nullish() |> Zoi.optional()
                       },
                       unrecognized_keys: :preserve
                     )

  @checkpoint_event_schema Zoi.map(
                             %{
                               "type" => Zoi.string(),
                               "data" => Zoi.string() |> Zoi.optional(),
                               "error" => Zoi.string() |> Zoi.optional(),
                               "message" => Zoi.string() |> Zoi.optional(),
                               "time" => Zoi.string() |> Zoi.optional(),
                               "timestamp" => Zoi.number() |> Zoi.optional()
                             },
                             unrecognized_keys: :preserve
                           )

  @policy_rule_schema Zoi.map(
                        %{
                          "domain" => Zoi.string() |> Zoi.optional(),
                          "action" => Zoi.string() |> Zoi.optional(),
                          "include" => Zoi.string() |> Zoi.optional()
                        },
                        unrecognized_keys: :preserve
                      )

  @policy_schema Zoi.map(
                   %{
                     "rules" => Zoi.array(@policy_rule_schema)
                   },
                   unrecognized_keys: :preserve
                 )

  @service_state_schema Zoi.map(
                          %{
                            "name" => Zoi.string() |> Zoi.optional(),
                            "status" => Zoi.string() |> Zoi.optional(),
                            "pid" => Zoi.integer() |> Zoi.optional(),
                            "started_at" => Zoi.string() |> Zoi.optional(),
                            "error" => Zoi.string() |> Zoi.optional()
                          },
                          unrecognized_keys: :preserve
                        )

  @service_schema Zoi.map(
                    %{
                      "name" => Zoi.string() |> Zoi.optional(),
                      "cmd" => Zoi.string(),
                      "args" => Zoi.array(Zoi.string()) |> Zoi.optional(),
                      "needs" => Zoi.array(Zoi.string()) |> Zoi.optional(),
                      "http_port" => Zoi.number() |> Zoi.nullish() |> Zoi.optional(),
                      "state" => @service_state_schema |> Zoi.optional()
                    },
                    unrecognized_keys: :preserve
                  )

  @service_log_files_schema Zoi.map(
                              %{
                                "combined" => Zoi.string() |> Zoi.optional(),
                                "stderr" => Zoi.string() |> Zoi.optional(),
                                "stdout" => Zoi.string() |> Zoi.optional()
                              },
                              unrecognized_keys: :preserve
                            )

  @service_log_event_schema Zoi.map(
                              %{
                                "type" => Zoi.string(),
                                "data" => Zoi.string() |> Zoi.optional(),
                                "message" => Zoi.string() |> Zoi.optional(),
                                "timestamp" => Zoi.number() |> Zoi.optional(),
                                "exit_code" => Zoi.number() |> Zoi.optional(),
                                "log_files" => @service_log_files_schema |> Zoi.optional()
                              },
                              unrecognized_keys: :preserve
                            )

  @exec_kill_event_schema Zoi.map(
                            %{
                              "type" => Zoi.string(),
                              "message" => Zoi.string() |> Zoi.optional(),
                              "signal" => Zoi.string() |> Zoi.optional(),
                              "pid" => Zoi.number() |> Zoi.optional(),
                              "exit_code" => Zoi.number() |> Zoi.optional(),
                              "timestamp" => Zoi.number() |> Zoi.optional()
                            },
                            unrecognized_keys: :preserve
                          )

  @exec_http_response_schema Zoi.map(
                               %{
                                 "session_id" =>
                                   Zoi.union([Zoi.string(), Zoi.integer()]) |> Zoi.optional(),
                                 "stdout" => Zoi.string() |> Zoi.optional(),
                                 "stderr" => Zoi.string() |> Zoi.optional(),
                                 "output" => Zoi.string() |> Zoi.optional(),
                                 "exit_code" => Zoi.number() |> Zoi.optional(),
                                 "status" => Zoi.string() |> Zoi.optional()
                               },
                               unrecognized_keys: :preserve
                             )

  @api_error_body_schema Zoi.map(
                           %{
                             "error" => Zoi.string() |> Zoi.optional(),
                             "message" => Zoi.string() |> Zoi.optional(),
                             "limit" => Zoi.integer() |> Zoi.optional(),
                             "window_seconds" => Zoi.integer() |> Zoi.optional(),
                             "retry_after_seconds" => Zoi.integer() |> Zoi.optional(),
                             "current_count" => Zoi.integer() |> Zoi.optional(),
                             "upgrade_available" => Zoi.boolean() |> Zoi.optional(),
                             "upgrade_url" => Zoi.string() |> Zoi.optional()
                           },
                           unrecognized_keys: :preserve
                         )

  @api_error_schema Zoi.map(
                      %{
                        "status" => Zoi.integer(),
                        "message" => Zoi.string(),
                        "body" => Zoi.string(),
                        "error_code" => Zoi.string() |> Zoi.nullish() |> Zoi.optional(),
                        "limit" => Zoi.integer() |> Zoi.nullish() |> Zoi.optional(),
                        "window_seconds" => Zoi.integer() |> Zoi.nullish() |> Zoi.optional(),
                        "retry_after_seconds" => Zoi.integer() |> Zoi.nullish() |> Zoi.optional(),
                        "current_count" => Zoi.integer() |> Zoi.nullish() |> Zoi.optional(),
                        "upgrade_available" => Zoi.boolean() |> Zoi.optional(),
                        "upgrade_url" => Zoi.string() |> Zoi.nullish() |> Zoi.optional(),
                        "retry_after_header" => Zoi.integer() |> Zoi.nullish() |> Zoi.optional(),
                        "rate_limit_limit" => Zoi.integer() |> Zoi.nullish() |> Zoi.optional(),
                        "rate_limit_remaining" =>
                          Zoi.integer() |> Zoi.nullish() |> Zoi.optional(),
                        "rate_limit_reset" => Zoi.integer() |> Zoi.nullish() |> Zoi.optional()
                      },
                      unrecognized_keys: :preserve
                    )

  @stream_message_schema Zoi.map(
                           %{
                             "type" => Zoi.string() |> Zoi.optional(),
                             "data" => Zoi.string() |> Zoi.optional(),
                             "error" => Zoi.string() |> Zoi.optional(),
                             "message" => Zoi.string() |> Zoi.optional(),
                             "time" => Zoi.string() |> Zoi.optional(),
                             "timestamp" => Zoi.number() |> Zoi.optional(),
                             "exit_code" => Zoi.number() |> Zoi.optional(),
                             "signal" => Zoi.string() |> Zoi.optional(),
                             "pid" => Zoi.number() |> Zoi.optional(),
                             "log_files" =>
                               Zoi.map(%{}, unrecognized_keys: :preserve) |> Zoi.optional()
                           },
                           unrecognized_keys: :preserve
                         )

  @spec parse_sprite(term()) :: {:ok, map()} | {:error, parse_error()}
  def parse_sprite(input), do: parse(@sprite_schema, input, :sprite)

  @spec parse_sprite_entry(term()) :: {:ok, map()} | {:error, parse_error()}
  def parse_sprite_entry(input), do: parse(@sprite_entry_schema, input, :sprite_entry)

  @spec parse_sprite_page(term()) :: {:ok, map()} | {:error, parse_error()}
  def parse_sprite_page(input), do: parse(@sprite_page_schema, input, :sprite_page)

  @spec parse_session(term()) :: {:ok, map()} | {:error, parse_error()}
  def parse_session(input), do: parse(@session_schema, input, :session)

  @spec parse_checkpoint(term()) :: {:ok, map()} | {:error, parse_error()}
  def parse_checkpoint(input), do: parse(@checkpoint_schema, input, :checkpoint)

  @spec parse_checkpoint_event(term()) :: {:ok, map()} | {:error, parse_error()}
  def parse_checkpoint_event(input), do: parse(@checkpoint_event_schema, input, :checkpoint_event)

  @spec parse_policy(term()) :: {:ok, map()} | {:error, parse_error()}
  def parse_policy(input), do: parse(@policy_schema, input, :policy)

  @spec parse_policy_rule(term()) :: {:ok, map()} | {:error, parse_error()}
  def parse_policy_rule(input), do: parse(@policy_rule_schema, input, :policy_rule)

  @spec parse_service(term()) :: {:ok, map()} | {:error, parse_error()}
  def parse_service(input), do: parse(@service_schema, input, :service)

  @spec parse_service_log_event(term()) :: {:ok, map()} | {:error, parse_error()}
  def parse_service_log_event(input),
    do: parse(@service_log_event_schema, input, :service_log_event)

  @spec parse_exec_kill_event(term()) :: {:ok, map()} | {:error, parse_error()}
  def parse_exec_kill_event(input), do: parse(@exec_kill_event_schema, input, :exec_kill_event)

  @spec parse_exec_http_response(term()) :: {:ok, map()} | {:error, parse_error()}
  def parse_exec_http_response(input), do: parse(@exec_http_response_schema, input, :exec_http)

  @spec parse_api_error_body(term()) :: {:ok, map()} | {:error, parse_error()}
  def parse_api_error_body(input), do: parse(@api_error_body_schema, input, :api_error_body)

  @spec parse_api_error(term()) :: {:ok, map()} | {:error, parse_error()}
  def parse_api_error(input), do: parse(@api_error_schema, input, :api_error)

  @spec parse_stream_message(term()) :: {:ok, map()} | {:error, parse_error()}
  def parse_stream_message(input), do: parse(@stream_message_schema, input, :stream_message)

  @spec parse(Zoi.schema(), term(), atom()) :: {:ok, map()} | {:error, parse_error()}
  def parse(schema, input, label) do
    case Zoi.parse(schema, input) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, errors} ->
        {:error, {:shape_error, label, errors}}
    end
  end
end
