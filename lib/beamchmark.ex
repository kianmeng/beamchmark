defmodule Beamchmark do
  @moduledoc """
  Top level module providing `Beamchmark.run/2` API.

  `#{inspect(__MODULE__)}` measures EVM performance while it is running user `#{inspect(__MODULE__)}.Scenario`.

  # Metrics being measured

  ## Scheduler Utilization

  At the moment, the main interest of `#{inspect(__MODULE__)}` is scheduler utilization which tells
  how much given scheduler was busy.
  Scheduler is busy when:
  * Executing process code
  * Executing linked-in driver or NIF code
  * Executing BIFs, or any other runtime handling
  * Garbage collecting
  * Handling any other memory management

  Scheduler utilization is measured using Erlang's [`:scheduler`](`:scheduler`) module which uses `:erlang.statistics/1`
  under the hood and it is represented as a floating point value between 0.0 and 1.0 and percent.

  `#{inspect(__MODULE__)}` measures following types of scheduler utilization:
  * normal/cpu/io - average utilization of single scheduler of given type
  * total normal/cpu/io - average utilization of all schedulers of given type. E.g total normal equals 1.0 when
  each of normal schedulers have been acive all the time
  * total - average utilization of all schedulers
  * weighted - average utilization of all schedulers weighted against maximum amount of available CPU time

  For more information please refer to `:erlang.statistics/1` (under `:scheduler_wall_time`) or `:scheduler.utilization/1`.

  ## Other

  Other metrics being measured:
  * reductions - total reductions number
  * context switches - total context switches number
  """

  @default_duration_s 60
  @default_cpu_interval_ms 1000
  @default_delay_s 0
  @default_formatter Beamchmark.Formatters.Console
  @default_output_dir Path.join([System.tmp_dir!(), "beamchmark"])
  @default_compare true

  @typedoc """
  Configuration for `#{inspect(__MODULE__)}`.
  * `name` - name of the benchmark. It can be used by formatters.
  * `duration` - time in seconds `#{inspect(__MODULE__)}` will be benchmarking EVM. Defaults to `#{@default_duration_s}` seconds.
  * `cpu_interval` - time in milliseconds `#{inspect(__MODULE__)}` will be benchmarking cpu usage. Defaults to `#{@default_cpu_interval_ms}` milliseconds. Needs to be greater than or equal to `interfere_timeout`.
  * `delay` - time in seconds `#{inspect(__MODULE__)}` will wait after running scenario and before starting benchmarking. Defaults to `#{@default_delay_s}` seconds.
  * `formatters` - list of formatters that will be applied to the result. By default contains only `#{inspect(@default_formatter)}`.
  * `compare?` - boolean indicating whether formatters should compare results for given scenario with the previous one. Defaults to `#{inspect(@default_compare)}.`
  * `output_dir` - directory where results of benchmarking will be saved. Defaults to "`beamchmark`" directory under location provided by `System.tmp_dir!/0`.
  """
  @type options_t() :: [
          name: String.t(),
          duration: pos_integer(),
          cpu_interval: pos_integer(),
          delay: non_neg_integer(),
          formatters: [Beamchmark.Formatter.t()],
          compare?: boolean(),
          output_dir: Path.t()
        ]

  @doc """
  Runs scenario and benchmarks EVM performance.

  If `compare?` option equals `true`, invocation of this function will also compare new measurements with the last ones.
  Measurements will be compared only if they share the same scenario module, delay and duration.
  """
  @spec run(Beamchmark.Scenario.t(), options_t()) :: :ok
  def run(scenario, opts \\ []) do
    config = %Beamchmark.Suite.Configuration{
      name: Keyword.get(opts, :name),
      duration: Keyword.get(opts, :duration, @default_duration_s),
      cpu_interval: Keyword.get(opts, :cpu_interval, @default_cpu_interval_ms),
      delay: Keyword.get(opts, :delay, @default_delay_s),
      formatters: Keyword.get(opts, :formatters, [@default_formatter]),
      compare?: Keyword.get(opts, :compare?, @default_compare),
      output_dir: Keyword.get(opts, :output_dir, @default_output_dir) |> Path.expand()
    }

    scenario
    |> Beamchmark.Suite.init(config)
    |> Beamchmark.Suite.run()
    |> tap(fn suite -> :ok = Beamchmark.Suite.save(suite) end)
    |> tap(fn suite -> :ok = Beamchmark.Formatter.output(suite) end)

    :ok
  end
end
