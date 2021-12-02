defmodule Beamchmark.SchedulerInfo do
  @moduledoc false
  # module representing different statistics about scheduler usage

  use Bunch.Access

  import Beamchmark.Math
  import Beamchmark.Utils

  alias Beamchmark.Math

  @type sched_usage_t :: %{
          (sched_id :: integer()) =>
            {util :: float(), percent :: Math.percent_t() | Math.percent_diff_t()}
        }
  @type total_sched_usage_t ::
          {util :: float(), percent :: Math.percent_t() | Math.percent_diff_t()}
  @type weighted_sched_usage_t ::
          {util :: float(), percent :: Math.percent_t() | Math.percent_diff_t()}

  @type t :: %__MODULE__{
          normal: sched_usage_t(),
          cpu: sched_usage_t(),
          io: sched_usage_t(),
          total_normal: total_sched_usage_t(),
          total_cpu: total_sched_usage_t(),
          total_io: total_sched_usage_t(),
          total: total_sched_usage_t(),
          weighted: weighted_sched_usage_t()
        }

  defstruct normal: %{},
            cpu: %{},
            io: %{},
            total_normal: {0, 0},
            total_cpu: {0, 0},
            total_io: {0, 0},
            total: {0, 0},
            weighted: {0, 0}

  # converts output of `:scheduler.utilization/1 to `SchedulerInfo.t()`
  @spec from_sched_util_result(any()) :: t()
  def from_sched_util_result(sched_util_result) do
    scheduler_info =
      sched_util_result
      |> Enum.reduce(%__MODULE__{}, fn
        {sched_type, sched_id, util, percent}, scheduler_info
        when sched_type in [:normal, :cpu, :io] ->
          # convert from charlist to string, remove trailing percent sign and convert to float
          percent = String.slice("#{percent}", 0..-2//1) |> String.to_float()
          put_in(scheduler_info, [sched_type, sched_id], {util, percent})

        {type, util, percent}, scheduler_info when type in [:total, :weighted] ->
          percent = String.slice("#{percent}", 0..-2//1) |> String.to_float()
          put_in(scheduler_info[type], {util, percent})
      end)

    total_normal = typed_total(scheduler_info.normal)
    total_cpu = typed_total(scheduler_info.cpu)
    total_io = typed_total(scheduler_info.io)

    %__MODULE__{
      scheduler_info
      | total_normal: total_normal,
        total_cpu: total_cpu,
        total_io: total_io
    }
  end

  @spec diff(t(), t()) :: t()
  def diff(base, new) do
    normal_diff = sched_usage_diff(base.normal, new.normal)
    cpu_diff = sched_usage_diff(base.cpu, new.cpu)
    io_diff = sched_usage_diff(base.io, new.io)

    total_normal_diff = sched_usage_diff(base.total_normal, new.total_normal)
    total_cpu_diff = sched_usage_diff(base.total_cpu, new.total_cpu)
    total_io_diff = sched_usage_diff(base.total_io, new.total_io)
    total_diff = sched_usage_diff(base.total, new.total)

    weighted_diff = sched_usage_diff(base.weighted, new.weighted)

    %__MODULE__{
      normal: normal_diff,
      cpu: cpu_diff,
      io: io_diff,
      total_normal: total_normal_diff,
      total_cpu: total_cpu_diff,
      total_io: total_io_diff,
      total: total_diff,
      weighted: weighted_diff
    }
  end

  defp typed_total(scheduler_usage) do
    count = scheduler_usage |> Map.keys() |> Enum.count()

    if count != 0 do
      util_sum =
        scheduler_usage
        |> Map.values()
        |> Enum.reduce(0, fn {util, _percent}, util_sum ->
          util_sum + util
        end)

      {util_sum / count, Float.round(util_sum / count * 100, 1)}
    else
      {0, 0}
    end
  end

  defp sched_usage_diff(base, new) when is_map(base) and is_map(new) do
    Enum.zip(base, new)
    |> Map.new(fn
      {{sched_id, {base_util, base_percent}}, {sched_id, {new_util, new_percent}}} ->
        {sched_id, {new_util - base_util, percent_diff(base_percent, new_percent)}}
    end)
  end

  defp sched_usage_diff({base_util, base_percent}, {new_util, new_percent}),
    do: {new_util - base_util, percent_diff(base_percent, new_percent)}

  @spec format(t()) :: binary()
  def format(scheduler_info) do
    format(scheduler_info, nil)
  end

  @spec format(t(), t() | nil) :: binary()
  def format(scheduler_info, nil) do
    """
    Normal schedulers
    --------------------
    #{do_format(scheduler_info.normal)}
    Total: #{do_format(scheduler_info.total_normal)}

    CPU schedulers
    --------------------
    #{do_format(scheduler_info.cpu)}
    Total: #{do_format(scheduler_info.total_cpu)}

    IO schedulers
    --------------------
    #{do_format(scheduler_info.io)}
    Total: #{do_format(scheduler_info.total_io)}

    Weighted
    --------------------
    #{do_format(scheduler_info.weighted)}\
    """
  end

  def format(scheduler_info, scheduler_info_diff) do
    """
    Normal schedulers
    --------------------
    #{do_format(scheduler_info.normal, scheduler_info_diff.normal)}
    Total: #{do_format(scheduler_info.total_normal, scheduler_info_diff.total_normal)}

    CPU schedulers
    --------------------
    #{do_format(scheduler_info.cpu, scheduler_info_diff.cpu)}
    Total: #{do_format(scheduler_info.total_cpu, scheduler_info_diff.total_cpu)}

    IO schedulers
    --------------------
    #{do_format(scheduler_info.io, scheduler_info_diff.io)}
    Total: #{do_format(scheduler_info.total_io, scheduler_info_diff.total_io)}

    Weighted
    --------------------
    #{do_format(scheduler_info.weighted, scheduler_info_diff.weighted)}\
    """
  end

  defp do_format(metric), do: do_format(metric, nil)

  defp do_format(sched_usage, nil) when is_map(sched_usage) do
    Enum.map_join(sched_usage, "\n", fn {sched_id, {util, percent}} ->
      "#{sched_id} #{util} #{percent}%"
    end)
  end

  defp do_format(sched_usage, sched_usage_diff)
       when is_map(sched_usage) and is_map(sched_usage_diff) do
    Enum.map_join(sched_usage, "\n", fn {sched_id, {util, percent}} ->
      {util_diff, percent_diff} = Map.get(sched_usage_diff, sched_id)
      color = get_color(percent_diff)

      "#{sched_id} #{util} #{percent}% #{color} #{util_diff} #{percent_diff}#{if percent_diff != :nan, do: "%"}#{IO.ANSI.reset()}"
    end)
  end

  # clauses for total and weighted usage
  defp do_format({util, percent}, nil) do
    "#{util} #{percent}%"
  end

  defp do_format({util, percent}, {util_diff, percent_diff}) do
    color = get_color(util_diff)

    "#{util} #{percent}% #{color} #{util_diff} #{percent_diff}#{if percent_diff != :nan, do: "%"}#{IO.ANSI.reset()}"
  end
end
