# Replay for Circuits

A testing library that can mock each of the [Circuits]{https://elixir-circuits.github.io/) libraries to 
step through and assert a sequence of calls and messages.


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

In your `test/test_helper.ex` file, call `Replay.setup_*`, which will perform the needed setup
for Replay for the each of the Circuits libraries you want to replay and the mocking backend (see below):

```elixir
Replay.setup_uart(:mimic)
Replay.setup_i2c(:mimic)
```

Additionally, it's likely that issue will arise if tests are run with `async: true` as the global mocking across processes can definitely overlap, so it's best to keep tests that rely on Circuits mocking running with `async: false`.

In this example, we are mocking the Circuits.UART and Circuits.I2C libraries with Mimic mocks.

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

### UART

```elixir
test "Successful sequence" do
  replay =
    Replay.UART.replay([
      {:write, "S0 T5"},
      {:read, "ACK"},
      {:write, "V34"},
      {:write, "R5531"},
      {:read, <<0xFF, 0xFF, 0xFE>>}
    ])

  {:ok, uart} = Circuits.UART.start_link()
  :ok = Circuits.UART.open(uart, "ttyAMA0", active: false)
  Circuits.UART.write(uart, "S0 T5")
  {:ok, "ACK"} = Circuits.UART.read(uart)
  Circuits.UART.write(uart, "V34")
  Circuits.UART.write(uart, "R5531")
  {:ok, <<0xFF, 0xFF, 0xFE>>} = Circuits.UART.read(uart)

  Replay.UART.assert_complete(replay)
end
```

### I2C

### GPIO

### SPI

Not implemented yet

## Mocking Libraries

Currently, Replay supports [Mimic](https://github.com/edgurgel/mimic) or [Resolve](https://github.com/amclain/resolve) as the underlying mocking library.  The main difference between these two libraries is the instrumentation of your project's code.  

Resolve provides "dependency injection and resolution at compile time or runtime" where each call to the original library is replaced with `resolve(Circuits.UART).write(...)` (for example). Resolve then replaces the module being called at runtime (or compile-time if configured).

In contrast, Mimic requires no changes to the code under test. From it's README: "Mimic works by copying your module out of the way and replacing it with one of it's own which can delegate calls back to the original or to a mock function as required."


