defmodule Replay.I2CMimicTest do
  use ExUnit.Case

  setup do
    Replay.setup_i2c(:mimic)
  end

  test "Successful sequence" do
    replay =
      Replay.replay_i2c([
        {:write, 0x47, "ABC"},
        {:read, 0x47, <<0xFF, 0xFF, 0xFE>>},
        {:write_read, 0x44, "XYZ0", "123"},
        {:write, 0x49, "ACK"}
      ])

    {:ok, pid} = Circuits.I2C.open("i2c-1")
    assert :ok = Circuits.I2C.write(pid, 0x47, "ABC")
    assert {:ok, <<0xFF, 0xFF, 0xFE>>} = Circuits.I2C.read(pid, 0x47, 3)
    assert {:ok, "123"} == Circuits.I2C.write_read(pid, 0x44, "XYZ0", 3)
    assert :ok = Circuits.I2C.write!(pid, 0x49, "ACK")

    Replay.assert_complete(replay)
  end

  test "out of sequence write" do
    _replay =
      Replay.replay_i2c([
        {:write, 0x47, <<0x01, 0x02>>},
        {:read, 0x55, "A"}
      ])

    {:ok, i2c} = Circuits.I2C.open("i2c-1")
    Circuits.I2C.write(i2c, 0x47, <<0x01, 0x02>>)

    assert catch_throw(Circuits.I2C.write(i2c, 0x44, "S0 T5"))
  end

  test "out of sequence read" do
    _replay =
      Replay.replay_i2c([
        {:write, 0x63, "S0"},
        {:read, 0x10, "ACK"},
        {:write, "A38"}
      ])

    {:ok, i2c} = Circuits.I2C.open("i2c-1")
    Circuits.I2C.write(i2c, 0x63, "S0")
    Circuits.I2C.read(i2c, 0x10, 3)

    assert catch_throw(Circuits.I2C.read(i2c, 0x10, 3))
  end

  test "out of sequence write_read" do
    Replay.replay_i2c([
      {:write, 0x63, "S0"},
      {:read, 0x10, "ACK"},
      {:write_read, 0x10, "A8", 2}
    ])

    {:ok, i2c} = Circuits.I2C.open("i2c-1")
    Circuits.I2C.write(i2c, 0x63, "S0")
    Circuits.I2C.read(i2c, 0x10, 3)

    assert catch_throw(Circuits.I2C.read(i2c, 0x10, 3))
  end

  test "write after complete" do
    Replay.replay_i2c([
      {:write, 0x63, "S0"},
      {:read, 0x10, "ACK"},
      {:write_read, 0x10, "A8", "00"}
    ])

    {:ok, i2c} = Circuits.I2C.open("i2c-1")
    Circuits.I2C.write(i2c, 0x63, "S0")
    Circuits.I2C.read(i2c, 0x10, 3)
    {:ok, "00"} = Circuits.I2C.write_read(i2c, 0x10, "A8", 2)

    assert catch_throw(Circuits.I2C.write(i2c, 0x10, "33"))
  end

  test "read after complete" do
    Replay.replay_i2c([
      {:write, 0x63, "S0"},
      {:read, 0x10, "ACK"},
      {:write_read, 0x10, "A8", "00"}
    ])

    {:ok, i2c} = Circuits.I2C.open("i2c-1")
    Circuits.I2C.write(i2c, 0x63, "S0")
    Circuits.I2C.read(i2c, 0x10, 3)
    {:ok, "00"} = Circuits.I2C.write_read(i2c, 0x10, "A8", 2)

    assert catch_throw(Circuits.I2C.write(i2c, 0x10, "33"))
  end

  test "write_read after complete" do
    Replay.replay_i2c([
      {:write, 0x63, "S0"},
      {:read, 0x10, "ACK"},
      {:write_read, 0x10, "A8", "00"}
    ])

    {:ok, i2c} = Circuits.I2C.open("i2c-1")
    Circuits.I2C.write(i2c, 0x63, "S0")
    Circuits.I2C.read(i2c, 0x10, 3)
    {:ok, "00"} = Circuits.I2C.write_read(i2c, 0x10, "A8", 2)

    assert catch_throw(Circuits.I2C.write_read(i2c, 0x10, "33", 2))
  end

  test "failed replay completion" do
    replay =
      Replay.replay_i2c([
        {:write, 0x63, "S0"},
        {:read, 0x10, "ACK"},
        {:write_read, 0x10, "A8", "00"}
      ])

    {:ok, i2c} = Circuits.I2C.open("i2c-1")
    Circuits.I2C.write(i2c, 0x63, "S0")

    assert catch_throw(Replay.assert_complete(replay))
  end

  test "await_complete should wait until the sequence is completed" do
    replay =
      Replay.replay_i2c([
        {:write, 0x63, "S0"},
        {:read, 0x10, "ACK"},
        {:write_read, 0x10, "A8", "00"}
      ])

    {:ok, i2c} = Circuits.I2C.open("i2c-1")
    Circuits.I2C.write(i2c, 0x63, "S0")
    Circuits.I2C.read(i2c, 0x10, 3)

    Task.async(fn ->
      :timer.sleep(150)
      {:ok, "00"} = Circuits.I2C.write_read(i2c, 0x10, "A8", 2)
    end)

    Replay.await_complete(replay)
    Replay.assert_complete(replay)
  end

  test "await_complete should throw if the sequence is not completed in time" do
    replay =
      Replay.replay_i2c([
        {:write, 0x63, "S0"},
        {:read, 0x10, "ACK"},
        {:write_read, 0x10, "A8", "00"}
      ])

    {:ok, i2c} = Circuits.I2C.open("i2c-1")
    Circuits.I2C.write(i2c, 0x63, "S0")
    Circuits.I2C.read(i2c, 0x10, 3)

    Task.async(fn ->
      :timer.sleep(150)
      {:ok, "00"} = Circuits.I2C.write_read(i2c, 0x10, "A8", 2)
    end)

    assert catch_throw(Replay.await_complete(replay, 50))
  end
end
