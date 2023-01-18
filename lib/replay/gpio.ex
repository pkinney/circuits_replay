defmodule Replay.GPIO do
  @moduledoc false

  import Replay.Common

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def build_mock(replay_id) do
    put_config(replay_id, :pins, %{})
    put_config(replay_id, :interrupts, %{})

    quote do
      def close(), do: :ok
      def info(), do: %{}

      def open(pin_number, pin_direction, _ \\ []) do
        ref = make_ref()
        :ok = put_pin(ref, pin_number, pin_direction)
        {:ok, ref}
      end

      def pin(gpio) do
        get_pin(gpio).pin_number
      end

      def set_direction(gpio, direction) do
        put_pin(gpio, get_pin(gpio).pin_number, direction)
      end

      def set_pull_mode(_, _), do: :ok

      def set_interrupts(gpio, trigger, opts \\ []) do
        put_interrupt(get_pin(gpio).pin_number, Keyword.get(opts, :receiver, self()))
        :ok
      end

      def read(gpio) do
        %{pin_number: pin_number, pin_direction: pin_direction} = get_pin(gpio)

        if pin_direction != :input do
          throw("Read was attempted on pin #{pin_number}, but that pin is set to `:output`")
        else
          case step(unquote(replay_id)) do
            {:read, ^pin_number, resp} ->
              maybe_send_next()
              resp

            nil ->
              throw(sequence_complete({:read, pin_number}))

            step ->
              throw(out_of_sequence({:read, pin_number}, step))
          end
        end
      end

      def write(gpio, value) do
        %{pin_number: pin_number, pin_direction: pin_direction} = get_pin(gpio)

        if pin_direction != :output do
          throw("Write was attempted on pin #{pin_number}, but that pin is set to `:input`")
        else
          case step(unquote(replay_id)) do
            {:write, ^pin_number, ^value} -> maybe_send_next()
            nil -> throw(sequence_complete({:write, pin_number, value}))
            step -> throw(out_of_sequence({:write, pin_number, value}, step))
          end
        end
      end

      defp maybe_send_next() do
        case current_step(unquote(replay_id)) do
          {:interrupt, pin, value} ->
            receiver = get_interrupt(pin)
            step(unquote(replay_id))
            timestamp = System.monotonic_time() |> System.convert_time_unit(:native, :nanosecond)
            send(receiver, {:circuits_gpio, pin, timestamp, value})
            maybe_send_next()

          _ ->
            :ok
        end
      end

      defp get_pin(ref) do
        get_config(unquote(replay_id), :pins) |> Map.get(ref)
      end

      defp put_pin(ref, pin_number, pin_direction) do
        pins =
          get_config(unquote(replay_id), :pins)
          |> Map.put(ref, %{pin_number: pin_number, pin_direction: pin_direction})

        put_config(unquote(replay_id), :pins, pins)
      end

      defp put_interrupt(pin, receiver) do
        interrupts =
          get_config(unquote(replay_id), :interrupts)
          |> Map.put(pin, receiver)

        put_config(unquote(replay_id), :interrupts, interrupts)
      end

      defp get_interrupt(pin) do
        get_config(unquote(replay_id), :interrupts)
        |> Map.get(pin)
      end
    end
  end
end
