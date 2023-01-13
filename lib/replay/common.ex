defmodule Replay.Common do
  @moduledoc false

  @type replay_id() :: integer()

  @spec create_table_if_needed() :: :ok
  def create_table_if_needed() do
    if :ets.whereis(:replay) == :undefined do
      :ets.new(:replay, [:public, :set, :named_table, read_concurrency: true])
    end

    :ok
  end

  @spec setup_mock(atom(), any) :: :ok
  def setup_mock(:mimic, module) do
    set_mock_type(:mimic)
    {:ok, _} = Application.ensure_all_started(:mimic)
    Mimic.copy(module)
  end

  def setup_mock(:resolve, _), do: set_mock_type(:resolve)
  def setup_mock(mock, _), do: throw("Unknown mock back-end: #{mock}")

  defp set_mock_type(mock) do
    :ets.insert(:replay, {:mock, mock})
    :ok
  end

  defp get_mock_type() do
    :ets.lookup_element(:replay, :mock, 2)
  end

  def inject_module(replay_id, module, body) do
    {:module, injected_module, _, _} =
      Module.create(:"Replay#{replay_id}", body, Macro.Env.location(__ENV__))

    case get_mock_type() do
      :resolve ->
        Resolve.inject(module, injected_module)

      :mimic ->
        Mimic.set_mimic_global()
        Mimic.stub_with(module, injected_module)
    end

    :ok
  end

  @spec generate_replay_id() :: replay_id()
  def generate_replay_id() do
    System.unique_integer([:positive])
  end

  @spec insert_sequence(replay_id(), list(tuple()), map() | nil) :: :ok
  def insert_sequence(replay_id, sequence, config \\ %{}) do
    true = :ets.insert(:replay, {replay_id, 0, sequence, config})
    :ok
  end

  def put_config(replay_id, key, value) do
    case :ets.lookup_element(:replay, replay_id, 4) do
      nil ->
        {:error, :replay_not_found}

      map ->
        map = Map.put(map, key, value)
        true = :ets.update_element(:replay, replay_id, {4, map})
        :ok
    end
  end

  def get_config(replay_id, key) do
    case :ets.lookup_element(:replay, replay_id, 4) do
      nil -> nil
      map -> Map.get(map, key)
    end
  end

  def current_step(replay_id) do
    sequence(replay_id) |> Enum.at(current_index(replay_id))
  end

  def current_index(replay_id) do
    :ets.lookup_element(:replay, replay_id, 2)
  end

  def step(replay_id) do
    index = :ets.update_counter(:replay, replay_id, {2, 1})
    sequence(replay_id) |> Enum.at(index - 1)
  end

  def sequence(replay_id) do
    :ets.lookup_element(:replay, replay_id, 3)
  end

  def complete?(replay_id) do
    current_index(replay_id) >= length(sequence(replay_id))
  end

  def assert_complete(replay_id) do
    sequence = sequence(replay_id)
    index = current_index(replay_id)

    if current_index(replay_id) >= length(sequence(replay_id)) do
      :ok
    else
      remaining = sequence |> Enum.drop(index)

      remaining_str = remaining |> Enum.map_join("\n", &"  - #{inspect(&1, base: :hex)}")

      throw("[Sequence Incomplete] #{length(remaining)} steps remaining: \n#{remaining_str}")
    end
  end

  def await_complete(replay_id, timeout) when timeout < 0 do
    assert_complete(replay_id)
  end

  def await_complete(replay_id, timeout) do
    if complete?(replay_id) do
      :ok
    else
      :timer.sleep(10)
      await_complete(replay_id, timeout - 10)
    end
  end

  def out_of_sequence(actual, expected) do
    "[Out of Sequence] \n   - expected: #{inspect(expected, base: :hex)} \n   - got: #{inspect(actual, base: :hex)}"
  end

  def sequence_complete(actual) do
    "[Out of Sequence] Replay is complete but received #{inspect(actual, base: :hex)}"
  end
end
