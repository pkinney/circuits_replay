defmodule Replay.I2C do
  def setup(mock) do
    if :ets.whereis(:i2c_replay) == :undefined do
      :ets.new(:i2c_replay, [:public, :set, :named_table, read_concurrency: true])
    end

    :ets.insert(:i2c_replay, {:mock, mock})

    case mock do
      :mimic ->
        IO.puts("Setting up Mimic mock backend...")
        Mimic.copy(Circuits.I2C)

      :resolve ->
        :ok

      _ ->
        throw("Unknown mock back-end: #{mock}")
    end
  end

  def replay(sequence, opts \\ []) do
    Mimic.set_mimic_global()
    mock = :ets.lookup_element(:i2c_replay, :mock, 2)
    devices = Keyword.get(opts, :devices, devices_from_sequence(sequence))
    bus_names = Keyword.get(opts, :busses, ["i2c-1"])

    replay_id = System.unique_integer([:positive])
    i2c_ref = make_ref() |> :erlang.ref_to_list()
    :ets.insert(:i2c_replay, {replay_id, 0, sequence, :running})

    macro =
      quote do
        def bus_names(), do: unquote(bus_names)
        def detect_devices(), do: unquote(devices)

        def device_present?(_i2c, address), do: detect_devices() |> Enum.member?(address)

        def open(bus_name) do
          {:ok, unquote(i2c_ref) |> :erlang.list_to_ref()}
        end

        def read(_, address, bytes_to_read, _opts \\ []) do
          case step() do
            {:read, ^address, resp} when byte_size(resp) == bytes_to_read -> {:ok, resp}
            nil -> throw(sequence_complete({:read, address, bytes_to_read}))
            step -> throw(out_of_sequence({:read, address, bytes_to_read}, step))
          end
          |> mark_if_completed()
        end

        def read!(i2c_bus, address, bytes_to_read, opts \\ []) do
          {:ok, resp} = read(i2c_bus, address, bytes_to_read, opts)
          resp
        end

        def write(_, address, data, _opts \\ []) do
          case step() do
            {:write, ^address, ^data} -> :ok
            nil -> throw(sequence_complete({:write, address, data}))
            step -> throw(out_of_sequence({:write, address, data}, step))
          end
          |> mark_if_completed()
        end

        def write!(i2c_bus, address, data, opts \\ []) do
          :ok = write(i2c_bus, address, data, opts)
        end

        def write_read(_, address, write, bytes, _ \\ []) do
          case step() do
            {:write_read, ^address, ^write, resp} when byte_size(resp) == bytes -> {:ok, resp}
            nil -> throw(sequence_complete({:write_read, address, write, bytes}))
            step -> throw(out_of_sequence({:write_read, address, write, bytes}, step))
          end
          |> mark_if_completed()
        end

        def write_read!(i2c_bus, address, write_data, bytes_to_read, opts \\ []) do
          {:ok, resp} = write_read(i2c_bus, address, write_data, bytes_to_read, opts)
          resp
        end

        defp step() do
          index = :ets.update_counter(:i2c_replay, unquote(replay_id), {2, 1})
          [{_, _, sequence, _}] = :ets.lookup(:i2c_replay, unquote(replay_id))
          sequence |> Enum.at(index - 1)
        end

        defp mark_if_completed(resp) do
          case :ets.lookup(:i2c_replay, unquote(replay_id)) do
            [{_, index, sequence, :running}] when index >= length(sequence) ->
              :ets.insert(:i2c_replay, {unquote(replay_id), index, sequence, :complete})

            _ ->
              :ok
          end

          resp
        end

        defp out_of_sequence(actual, expected) do
          "[Out of Sequence] \n   - expected: #{inspect(expected)} \n   - got: #{inspect(actual)}"
        end

        defp sequence_complete(actual) do
          "[Out of Sequence] Replay is complete but received #{inspect(actual)}"
        end
      end

    {:module, injected_module, _, _} =
      Module.create(:"Replay#{replay_id}", macro, Macro.Env.location(__ENV__))

    case mock do
      :resolve -> Resolve.inject(Circuits.I2C, injected_module)
      :mimic -> Mimic.stub_with(Circuits.I2C, injected_module)
    end

    replay_id
  end

  def assert_complete(replay_id) do
    case :ets.lookup(:i2c_replay, replay_id) do
      [{_, _, _, :complete}] ->
        :ok

      [{_, index, sequence, :running}] ->
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
    case :ets.lookup(:i2c_replay, replay_id) do
      [{_, index, sequence, :running}] ->
        remaining = sequence |> Enum.drop(index)

        remaining_str =
          remaining |> Enum.map(&"  - #{inspect(&1, base: :hex)}") |> Enum.join("\n")

        throw("[Sequence Incomplete] #{length(remaining)} steps remaining: \n#{remaining_str}")

      [{_, _, :complete}] ->
        :ok
    end
  end

  def await_complete(replay_id, timeout) do
    case :ets.lookup(:i2c_replay, replay_id) do
      [{_, _, _, :complete}] ->
        :ok

      _ ->
        :timer.sleep(10)
        await_complete(replay_id, timeout - 10)
    end
  end

  defp devices_from_sequence(sequence) do
    sequence |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
  end
end
