defmodule Timber.Events.ExceptionEvent do
  @moduledoc """
  The `ExceptionEvent` is used to track exceptions.

  Timber automatically tracks and structures exceptions in your application. Giving
  you detailed stack traces, context, and exception data.
  """

  @type stacktrace_entry :: {
    module,
    atom,
    arity,
    [file: IO.chardata, line: non_neg_integer] | []
  }

  @type backtrace_entry :: %{
    function: String.t,
    file: String.t | nil,
    line: non_neg_integer | nil
  }

  @type t :: %__MODULE__{
    backtrace: [backtrace_entry] | [],
    name: String.t,
    message: String.t,
  }

  @enforce_keys [:backtrace, :name, :message]
  defstruct [:backtrace, :name, :message]

  @doc """
  Builds a new struct taking care to normalize data into a valid state. This should
  be used, where possible, instead of creating the struct directly.
  """
  @spec new(String.t) :: {:ok, t} | {:error, atom}
  def new(log_message) do
    lines =
      log_message
      |> String.split("\n")
      |> Enum.map(&({&1, String.trim(&1)}))

    case do_new({nil, "", []}, lines) do
      {name, message, backtrace} when is_binary(name) and length(backtrace) > 0 ->
        {:ok, %__MODULE__{name: name, message: message, backtrace: backtrace}}

      _ ->
        {:error, :could_not_parse_message}
    end
  end

  # ** (exit) an exception was raised:
  defp do_new({nil, message, [] = backtrace}, [{_raw_line, ("** (exit) " <> _suffix)} | lines]) do
    do_new({nil, message, backtrace}, lines)
  end

  #    ** (RuntimeError) my message
  defp do_new({nil, _message, [] = backtrace}, [{_raw_line, ("** (" <> line_suffix)} | lines]) do
    # Using split since it is more performance with binary scanning
    [name, message] = String.split(line_suffix, ")", parts: 2)
    do_new({name, message, backtrace}, lines)
  end

  # Ignore other leading messages
  defp do_new({nil, _message, _backtrace} = acc, [_line | lines]), do: do_new(acc, lines)

  #      (odin_client_api) web/controllers/page_controller.ex:5: Odin.ClientAPI.PageController.index/2
  defp do_new({name, message, backtrace}, [{_raw_line, ("(" <> line_suffix)} | lines]) when not is_nil(name) and not is_nil(message) do
    # Using split since it is more performance with binary scanning
    [app_name, line_suffix] = String.split(line_suffix, ")", parts: 2)
    [file, line_suffix] = String.split(line_suffix, ":", parts: 2)
    [line_number, function] = String.split(line_suffix, ":", parts: 2)
    line = %{
      app_name: app_name,
      function: String.trim(function),
      file: String.trim(file),
      line: parse_line_number(line_number)
    }
    do_new({name, message, [line | backtrace]}, lines)
  end

  # Ignore lines we don't recognize.
  defp do_new(acc, [_line | lines]), do: do_new(acc, lines)

  # Finish the iteration, reversing the backtrace for performance reasons.
  defp do_new({name, message, backtrace}, []) do
    {name, String.trim(message), Enum.reverse(backtrace)}
  end

  defp parse_line_number(line_str) do
    case Integer.parse(line_str) do
      {line, _unit} -> line
      :error -> nil
    end
  end

  @doc """
  Message to be used when logging.
  """
  @spec message(t) :: IO.chardata
  def message(%__MODULE__{name: name, message: message}), do: [?(, name, ?), ?\s, message]
end
