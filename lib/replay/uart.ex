defmodule Replay.UART do
  def setup() do
    if :ets.whereis(:uart_replay) == :undefined do
      :ets.new(:uart_replay, [:public, :set, :named_table, read_concurrency: true])
    end
  end

  def replay(sequence) do
    replay_id = make_ref() |> :erlang.ref_to_list()
    :ets.insert(:uart_replay, {replay_id, 0, sequence, true, nil, nil})

    # TODO allow passing options and pid during replay

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
          result =
            case step() do
              {:write, ^data} -> maybe_send_next()
              nil -> throw(sequence_complete({:write, data}))
              step -> throw(out_of_sequence({:write, data}, step))
            end

          mark_if_completed()
          result
        end

        def read(_, _ \\ 5_000) do
          result =
            case step() do
              {:read, data} -> {:ok, data}
              nil -> throw(sequence_complete(:read))
              step -> throw(out_of_sequence(:read, step))
            end

          mark_if_completed()
          result
        end

        def drain(_, _ \\ 5_000), do: :ok

        defp step() do
          index = :ets.update_counter(:uart_replay, unquote(replay_id), {2, 1})
          unquote(sequence) |> Enum.at(index - 1)
        end

        defp maybe_send_next() do
          [{_, index, _, active, parent, name}] = :ets.lookup(:uart_replay, unquote(replay_id))

          if active do
            case Enum.at(unquote(sequence), index) do
              {:read, message} ->
                :ets.update_counter(:uart_replay, unquote(replay_id), {2, 1})
                send(parent, {:circuits_uart, name, message})
                maybe_send_next()
                mark_if_completed()

              _ ->
                :ok
            end
          else
            :ok
          end
        end

        defp mark_if_completed() do
          case :ets.lookup(:uart_replay, unquote(replay_id)) do
            [{_, index, sequence, _, _, _}] when index >= length(sequence) ->
              :ets.insert(:uart_replay, {unquote(replay_id), index, :complete})

            _ ->
              :ok
          end
        end

        defp out_of_sequence(actual, expected) do
          "[Out of Sequence] \n   - expected: #{inspect(expected, base: :hex)} \n   - got: #{inspect(actual, base: :hex)}"
        end

        defp sequence_complete(actual) do
          "[Out of Sequence] Replay is complete but received #{inspect(actual, base: :hex)}"
        end
      end
    )

    replay_id
  end

  def assert_complete(replay_id) do
    case :ets.lookup(:uart_replay, replay_id) do
      [{_, _, :complete}] ->
        :ok

      [{_, index, sequence, _, _, _}] ->
        remaining = sequence |> Enum.drop(index)

        remaining_str =
          remaining |> Enum.map(&"  - #{inspect(&1, base: :hex)}") |> Enum.join("\n")

        throw("[Sequence Incomplete] #{length(remaining)} steps remaining: \n#{remaining_str}")

      _ ->
        throw("Replay not found")
    end
  end

  def await_complete(replay_id, timeout \\ 5_000)

  def await_complete(replay_id, timeout) when timeout < 0 do
    case :ets.lookup(:uart_replay, replay_id) do
      [{_, index, sequence, _, _, _}] ->
        remaining = sequence |> Enum.drop(index)

        remaining_str =
          remaining |> Enum.map(&"  - #{inspect(&1, base: :hex)}") |> Enum.join("\n")

        throw("[Sequence Incomplete] #{length(remaining)} steps remaining: \n#{remaining_str}")

      [{_, _, :complete}] ->
        :ok
    end
  end

  def await_complete(replay_id, timeout) do
    case :ets.lookup(:uart_replay, replay_id) do
      [{_, _, :complete}] ->
        :ok

      _ ->
        :timer.sleep(10)
        await_complete(replay_id, timeout - 10)
    end
  end
end
