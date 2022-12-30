defmodule Replay.UART do
  def replay(sequence) do
    if :ets.whereis(:uart_replay) == :undefined do
      :ets.new(:uart_replay, [:public, :set, :named_table, read_concurrency: true])
    end

    replay_id = make_ref() |> :erlang.ref_to_list()
    :ets.insert(:uart_replay, {replay_id, 0, sequence, true, nil, nil})

    Resolve.inject(
      Circuits.UART,
      quote do
        def start_link(_ \\ []) do
          true = :ets.update_element(:uart_replay, unquote(replay_id), {5, self()})
          {:ok, :erlang.list_to_ref(unquote(replay_id))}
        end

        def open(pid, name, opts \\ []) do
          active = Keyword.get(opts, :active, true)
          true = :ets.update_element(:uart_replay, unquote(replay_id), {4, active})
          true = :ets.update_element(:uart_replay, unquote(replay_id), {6, name})

          :ok
        end

        def write(_, data) do
          case step() do
            {:write, ^data} ->
              maybe_send_next()

            nil ->
              throw(
                "[Out of Sequence] Replay is complete but received #{inspect({:write, data})}"
              )

            step ->
              throw(
                "[Out of Sequence] \n   - expected: #{inspect(step)} \n   - got: #{inspect({:write, data})}"
              )
          end
        end

        def read(_, _ \\ 5_000) do
          case step() do
            {:read, data} -> {:ok, data}
            nil -> throw("[Out of Sequence] Replay is complete but received :read")
            step -> throw("{:out_of_sequence, step, :read}")
          end
        end

        defp step() do
          index = :ets.update_counter(:uart_replay, unquote(replay_id), {2, 1})
          unquote(sequence) |> Enum.at(index - 1)
        end

        # defp peek() do
        #   index = :ets.lookup_element(:uart_replay, unquote(replay_id), 2)
        #   unquote(sequence) |> Enum.at(index)
        # end

        defp maybe_send_next() do
          [{_, index, _, active, parent, name}] = :ets.lookup(:uart_replay, unquote(replay_id))

          if active do
            case Enum.at(unquote(sequence), index) do
              {:read, message} ->
                :ets.update_counter(:uart_replay, unquote(replay_id), {2, 1})
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
    )

    replay_id
  end

  def assert_complete(replay_id) do
    case :ets.lookup(:uart_replay, replay_id) do
      [{_, index, sequence, _, _, _}] when index >= length(sequence) ->
        :ok

      [{_, index, sequence, _, _, _}] ->
        remaining = sequence |> Enum.drop(index)
        remaining_str = remaining |> Enum.map(&"  - #{inspect(&1)}") |> Enum.join("\n")
        throw("[Sequence Incomplete] #{length(remaining)} steps remaining: \n#{remaining_str}")

      _ ->
        throw("Replay not found")
    end
  end
end
