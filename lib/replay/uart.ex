defmodule Replay.UART do
  alias Replay.Common

  def setup(mock) do
    Common.create_table_if_needed()
    Common.setup_mock(mock, Circuits.UART)
  end

  def build_mock(replay_id) do
    quote do
      def start_link(_ \\ []) do
        ref = make_ref()
        :ok = Common.put_config(unquote(replay_id), :ref, ref)
        :ok = Common.put_config(unquote(replay_id), :parent, self())
        {:ok, ref}
      end

      def open(pid, name, opts \\ []) do
        active = Keyword.get(opts, :active, true)
        :ok = Common.put_config(unquote(replay_id), :active, active)
        :ok = Common.put_config(unquote(replay_id), :name, name)
        :ok
      end

      def write(_, data) do
        result =
          case Common.step(unquote(replay_id)) do
            {:write, ^data} -> maybe_send_next()
            nil -> throw(sequence_complete({:write, data}))
            step -> throw(out_of_sequence({:write, data}, step))
          end

        # mark_if_completed()
        result
      end

      def read(_, _ \\ 5_000) do
        result =
          case Common.step(unquote(replay_id)) do
            {:read, data} -> {:ok, data}
            nil -> throw(sequence_complete(:read))
            step -> throw(out_of_sequence(:read, step))
          end

        # mark_if_completed()
        result
      end

      def drain(_, _ \\ 5_000), do: :ok

      defp maybe_send_next() do
        active = Common.get_config(unquote(replay_id), :active)

        if active do
          case Common.current_step(unquote(replay_id)) do
            {:read, message} ->
              parent = Common.get_config(unquote(replay_id), :parent)
              name = Common.get_config(unquote(replay_id), :name)
              Common.step(unquote(replay_id))
              send(parent, {:circuits_uart, name, message})
              maybe_send_next()

            # mark_if_completed()

            _ ->
              :ok
          end
        else
          :ok
        end
      end

      # defp mark_if_completed() do
      #   case :ets.lookup(:uart_replay, unquote(replay_id)) do
      #     [{_, index, sequence, _, _, _}] when index >= length(sequence) ->
      #       :ets.insert(:uart_replay, {unquote(replay_id), index, :complete})
      #
      #     _ ->
      #       :ok
      #   end
      # end

      defp out_of_sequence(actual, expected) do
        "[Out of Sequence] \n   - expected: #{inspect(expected, base: :hex)} \n   - got: #{inspect(actual, base: :hex)}"
      end

      defp sequence_complete(actual) do
        "[Out of Sequence] Replay is complete but received #{inspect(actual, base: :hex)}"
      end
    end
  end
end
