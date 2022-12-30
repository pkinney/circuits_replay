defmodule Replay.I2C do
  def replay(sequence, opts \\ []) do
    devices = Keyword.get(opts, :devices, devices_from_sequence(sequence))
    bus_names = Keyword.get(opts, :busses, ["i2c-1"])

    if :ets.whereis(:i2c_replay) == :undefined do
      :ets.new(:i2c_replay, [:public, :set, :named_table, read_concurrency: true])
    end

    replay_id = make_ref() |> :erlang.ref_to_list()
    :ets.insert(:i2c_replay, {replay_id, 0, sequence})

    Resolve.inject(
      Circuits.I2C,
      quote do
        def bus_names(), do: unquote(bus_names)
        def detect_devices(_), do: unquote(devices)

        def device_present?(_i2c, address), do: detect_devices() |> Enum.member?(address)
        # discover(possible_addresses, present? \\ &device_present?/2)
        # discover_one(possible_addresses, present? \\ &device_present?/2)
        # discover_one!(possible_addresses, present? \\ &device_present?/2)
        # info()
        def open(bus_name) do
          {:ok, :erlang.list_to_ref(unquote(replay_id))}
        end

        def read(_, address, bytes_to_read, _opts \\ []) do
          case step() do
            {:read, ^address, resp} when byte_size(resp) == bytes_to_read -> {:ok, resp}
            nil -> throw(sequence_complete({:read, address, bytes_to_read}))
            step -> throw(out_of_sequence({:read, address, byte_to_read}, step))
          end
        end

        def read!(i2c_bus, address, bytes_to_read, opts \\ []) do
          {:ok, resp} = read(i2c_bus, address, bytes_to_read, opts)
        end

        def write(_, address, data, _opts \\ []) do
          case step() do
            {:write, ^address, ^data} -> :ok
            nil -> throw(sequence_complete({:write, address, data}))
            step -> throw(out_of_sequence({:write, address, data}, step))
          end
        end

        def write!(i2c_bus, address, data, opts \\ []) do
          :ok = write(i2c_bus, address, data, opts)
        end

        def write_read(_, addr, write, bytes, _ \\ []) do
          case step() do
            {:write_read, ^address, ^write, resp} when byte_size(resp) == bytes -> {:ok, resp}
            nil -> throw(sequence_complete({:write_read, addr, write, bytes}))
            step -> throw(out_of_sequence({:write_read, addr, write, bytes}, step))
          end
        end

        def write_read!(i2c_bus, address, write_data, bytes_to_read, opts \\ []) do
          {:ok, resp} = write_read(i2c_bus, address, write_data, bytes_to_read, opts)
        end

        defp step() do
          index = :ets.update_counter(:i2c_replay, unquote(replay_id), {2, 1})
          unquote(sequence) |> Enum.at(index - 1)
        end

        defp out_of_sequence(actual, expected) do
          "[Out of Sequence] \n   - expected: #{inspect(expected)} \n   - got: #{inspect(actual)}"
        end

        defp sequence_complete(actual) do
          "[Out of Sequence] Replay is complete but received #{inspect(actual)}"
        end
      end
    )

    replay_id
  end

  defp devices_from_sequence(sequence) do
    sequence |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
  end
end
