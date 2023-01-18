# Replay for Circuits

![Build Status](https://github.com/pkinney/replay/actions/workflows/ci.yaml/badge.svg)
[![Hex.pm](https://img.shields.io/hexpm/v/replay.svg)](https://hex.pm/packages/replay)
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/replay)

A testing library that can mock each of the [Circuits](https://elixir-circuits.github.io/) libraries (at least UART, I2C, and GPIO for now) to step through and assert a sequence of calls and messages.

(For now, this library is focused only on the basic communication functions of each of the libraries.  Items such as pull-up/pull-down in Circuits.GPIO or device enumeration in Circuits.UART and Circuits.I2C are not implemented.)

## Installation

The package can be installed by adding `replay` to your list of dependencies in `mix.exs` along with 
either of the supported mocking libraries:

```elixir
def deps do
  [
    {:replay, "~> 0.1.0", only: :test},
    {:resolve, "~> 0.1.0", only: :test},
    # or {:mimic, "~> 1.7", only: :test}
  ]
end
```

## Usage

### Setup

In your `test/test_helper.exs` file, call `Replay.setup_*`, which will perform the needed setup
for Replay for the each of the Circuits libraries you want to replay and the mocking backend (see below):

```elixir
Replay.setup_uart(:mimic)
Replay.setup_i2c(:mimic)
```

In the above example, we are mocking the `Circuits.UART` and `Circuits.I2C` libraries with Mimic mocks.

Additionally, it's likely that issue will arise if tests are run with `async: true` as the global mocking across processes can definitely overlap, so it's best to keep tests that rely on Circuits mocking running with `async: false`.

### Replay Steps

At the point that you want to start mocking calls with a replay, call the `replay/1` function of
the replay module you are mocking and pass a list of steps.  The format of these steps varies slightly
between each of the libraries, but using UART as an example:

```elixir
Replay.UART.replay([
  {:write, <<0xFF, 0xFE, 0xAD, 0x01>>},
  {:read, <<0x0F, 0x10>>}
])
```

will expect something to write `<<0xFF, 0xFE, 0xAD, 0x01>>` to serial line and then it will (in the 
active UART mode) send `<<0x0F, 0x10>>` to the parent process of the Circuit.UART process.

```elixir
Replay.UART.replay([
  {:write, <<0xFF, 0xFE, 0xAD, 0x01>>},
  {:read, <<0x0F, 0x10>>}
])

{:ok, uart} = Circuits.UART.start_link()
:ok = Circuits.UART.open(uart, "ttyAMA0", active: true)
Circuits.UART.write(uart, <<0xFF, 0xFE, 0xAD, 0x01>>)
assert_received({:circuits_uart, "ttyAMA0", <<0x0F, 0x10>>})
```

If a message is received out of sequence, an error is thrown:

```elixir
Replay.UART.replay([
  {:write, <<0xFF, 0xFE, 0xAD, 0x01>>},
  {:write, <<0x34, 0xDF>>},
  {:read, <<0x0F, 0x10>>}
])

{:ok, uart} = Circuits.UART.start_link()
:ok = Circuits.UART.open(uart, "ttyAMA0", active: false)
Circuits.UART.write(uart, <<0xFF, 0xFE, 0xAD, 0x01>>)

# The call to `read` will throw an error since the replay expects `<<0x34, 0xDF>>` to be
# written to the serial line before the read request.
Circuits.UART.read()
``` 

### Ensuring/Waiting on Completion

`Replay.assert_complete/1` will throw and error if all steps in the sequence are not successfully
completed.

```elixir
replay =
  Replay.UART.replay([
    {:write, <<0xFF, 0xFE, 0xAD, 0x01>>},
    {:read, <<0x0F, 0x10>>}
  ])

{:ok, uart} = Circuits.UART.start_link()
:ok = Circuits.UART.open(uart, "ttyAMA0", active: false)
assert_received({:circuits_uart, "ttyAMA0", <<0x0F, 0x10>>})

# The following will throw and error since the last step in the sequence has not completed.
assert_complete(replay) 
``` 

In cases where there handling of Circuits interaction is happening in a separate process, it may be useful to wait for completion with a given timeout:

```elixir
Replay.await_complete(replay, 50)
```

The above will continuously check whether the sequence is complete and return `:ok` if the sequence completes within 50ms or will throw if it is not complete after 50ms has elapsed. 

### Circuits.UART

Replays can be built with the following two steps:

* **`{:write, binary}`** - expects a call to `Circuits.UART.write(pid, binary)` with the exact binary.
* **`{:read, binary}`** - either 1) return the given binary in response to a call to `Circuits.UART.read(pid)` when the port is opened as `active: false` or 2) send a message to the parent process when the port is opened as `active: true` (or when `active` is not specified as this is the default).

Currently, there is only a tenuous connection between the sequence and any particular Circuits.UART process/PID, so it's possible that different processes may step on each other if their execution overlaps.

### Circuits.I2C

Replays can contain the following steps:

* **`{:write, address, binary}`** - expects a call to `Circuits.I2C.write(pid, address, binary)`
* **`{:read, address, binary}`** - expects a call to `Circuits.I2C.read(pid, address, size)` and ensures that the value of `size` is the exact length of the `binary` in the step.  The contents of `binary` will be returned.
* **`{:write_read, address, binary1, binary2}`** - expects a call to `Circuits.write_read(pid, address, binary1, size)` where the value of `size` is the exact length of `binary2`.

```elixir
replay =
  Replay.replay_i2c([
    {:write, 0x47, "ABC"},
    {:read, 0x47, <<0xFF, 0xFF, 0xFE>>},
    {:write_read, 0x44, "XYZ0", "123"},
    {:write, 0x49, "ACK"}
  ])

{:ok, pid} = i2c().open("i2c-1")
assert :ok = i2c().write(pid, 0x47, "ABC")
assert {:ok, <<0xFF, 0xFF, 0xFE>>} = i2c().read(pid, 0x47, 3)
assert {:ok, "123"} == i2c().write_read(pid, 0x44, "XYZ0", 3)
assert :ok = i2c().write!(pid, 0x49, "ACK")

Replay.assert_complete(replay)
```

### Circuits.GPIO

The GPIO replay tracks multiple GPIO pin configuartions and can replay input, output, and interrupts across them.  Replay steps can be any of the following:

* **`{:write, pin_number, value}`** - expects a call to `Circuits.GPIO.write(gpio, value)` where `gpio` is the reference for the pin number `pin_number`.
* **`{:read, pin_number, value}`** - expects a call to `Circuits.GPIO.read(gpio)` where `gpio` is the reference for the pin number `pin_number`, to which it will return `value`.
* **`{:interrupt, pin_number, value}`** - will send a message to the process registered for the interrupt on that pin. The message will match the message sent by Circuits.GPIO (`{:circuits_gpio, pin_number, timestamp, value}`).

```elixir
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
```

## Mocking Libraries

Currently, Replay supports [Mimic](https://github.com/edgurgel/mimic) or [Resolve](https://github.com/amclain/resolve) as the underlying mocking library.  The main difference between these two libraries is the instrumentation of your project's code.  

Resolve provides "dependency injection and resolution at compile time or runtime" where each call to the original library is replaced with `resolve(Circuits.UART).write(...)` (for example). Resolve then replaces the module being called at runtime (or compile-time if configured).

In contrast, Mimic requires no changes to the code under test. From it's README: "Mimic works by copying your module out of the way and replacing it with one of it's own which can delegate calls back to the original or to a mock function as required." Replay handles the setup and calling `Mimic.copy(...)` as needed.


