defmodule Replay.UART do
  @moduledoc false

  import Replay.Common

  def setup(mock) do
    create_table_if_needed()
    setup_mock(mock, Circuits.UART)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def build_mock(replay_id) do
    quote do
      def start_link(_ \\ []) do
        ref = make_ref()
        :ok = put_config(unquote(replay_id), :ref, ref)
        :ok = put_config(unquote(replay_id), :parent, self())
        {:ok, ref}
      end

      def open(pid, name, opts \\ []) do
        active = Keyword.get(opts, :active, true)
        :ok = put_config(unquote(replay_id), :active, active)
        :ok = put_config(unquote(replay_id), :name, name)
        :ok
      end

      def write(_, data) do
        case step(unquote(replay_id)) do
          {:write, ^data} -> maybe_send_next()
          nil -> throw(sequence_complete({:write, data}))
          step -> throw(out_of_sequence({:write, data}, step))
        end
      end

      def read(_, _ \\ 5_000) do
        case step(unquote(replay_id)) do
          {:read, data} -> {:ok, data}
          nil -> throw(sequence_complete(:read))
          step -> throw(out_of_sequence(:read, step))
        end
      end

      def drain(_, _ \\ 5_000), do: :ok

      defp maybe_send_next() do
        active = get_config(unquote(replay_id), :active)

        if active do
          case current_step(unquote(replay_id)) do
            {:read, message} ->
              parent = get_config(unquote(replay_id), :parent)
              name = get_config(unquote(replay_id), :name)
              step(unquote(replay_id))
              send(parent, {:circuits_uart, name, message})
              maybe_send_next()

            _ ->
              :ok
          end
        else
          :ok
        end
      end
    end
  end
end
