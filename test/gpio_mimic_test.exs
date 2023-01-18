defmodule Replay.GPIOMimicTest do
  use ExUnit.Case

  setup do
    Replay.setup_gpio(:mimic)
  end

  test "keeps track of pin numbers" do
    Replay.replay_gpio([])

    {:ok, pin1} = Circuits.GPIO.open(1, :output)
    {:ok, pin2} = Circuits.GPIO.open(2, :input)

    assert Circuits.GPIO.pin(pin1) == 1
    assert Circuits.GPIO.pin(pin2) == 2
  end

  test "keeps track of pin direction" do
    Replay.replay_gpio([{:read, 1, 0}])

    {:ok, pin} = Circuits.GPIO.open(1, :output)
    assert catch_throw(Circuits.GPIO.read(pin))

    :ok = Circuits.GPIO.set_direction(pin, :input)
    assert 0 == Circuits.GPIO.read(pin)
  end

  test "read and writes from multiple pins" do
    replay = Replay.replay_gpio([{:read, 1, 0}, {:write, 2, 1}, {:write, 2, 0}, {:read, 1, 1}])

    {:ok, pin1} = Circuits.GPIO.open(1, :input)
    {:ok, pin2} = Circuits.GPIO.open(2, :output)

    assert 0 == Circuits.GPIO.read(pin1)
    :ok = Circuits.GPIO.write(pin2, 1)
    :ok = Circuits.GPIO.write(pin2, 0)
    assert 1 == Circuits.GPIO.read(pin1)

    Replay.assert_complete(replay)
  end

  test "fails when writing the wrong value" do
    Replay.replay_gpio([{:read, 1, 0}, {:write, 2, 1}, {:write, 2, 0}, {:read, 1, 1}])

    {:ok, pin1} = Circuits.GPIO.open(1, :input)
    {:ok, pin2} = Circuits.GPIO.open(2, :output)

    assert 0 == Circuits.GPIO.read(pin1)
    :ok = Circuits.GPIO.write(pin2, 1)
    assert catch_throw(Circuits.GPIO.write(pin2, 1))
  end

  test "receive interrupts" do
    replay =
      Replay.replay_gpio([
        {:write, 1, 1},
        {:interrupt, 2, 1},
        {:interrupt, 2, 0}
      ])

    {:ok, pin1} = Circuits.GPIO.open(1, :output)
    {:ok, pin2} = Circuits.GPIO.open(2, :input)

    :ok = Circuits.GPIO.set_interrupts(pin2, :rising)

    :ok = Circuits.GPIO.write(pin1, 1)
    assert_received({:circuits_gpio, 2, _, 1})
    assert_received({:circuits_gpio, 2, _, 0})

    Replay.assert_complete(replay)
  end
end
