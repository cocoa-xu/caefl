defmodule CAEFL.Sensor do
  defmacro __using__(_opts) do
    quote do
      use GenServer
      @behaviour CAEFL.Sensor

      def start_link(init_param, opts \\ []) do
        GenServer.start_link(__MODULE__, init_param, opts)
      end

      def start(init_param, opts \\ []) do
        GenServer.start(__MODULE__, init_param, opts)
      end

      @impl true
      def init(init_param) do
        with {:ok, sensor_state} <- init_sensor(init_param) do
          {:ok, sensor_state}
        else
          {:error, err} -> {:error, err}
        end
      end

      @impl true
      def handle_call(:read_data, _from, sensor_state) do
        with {:ok, sample, sensor_state} <- read_data(sensor_state) do
          {:reply, sample, sensor_state}
        else
          {:error, err} -> {:error, err}
        end
      end
    end
  end

  @doc """
  Read one sample from the sensor.
  """
  def read_data(sensor) do
    GenServer.call(sensor, :read_data)
  end

  @doc """
  Sensor is expected to be initialised in this callback (if applicable).

  The `init_param` argument is forwarded from `GenServer.start/start_link`.

  The return value represents the state of current sensor.
  """
  @callback init_sensor(init_param :: term) ::
    {:ok, sensor_state :: term}
    | {:error, reason :: term}

  @doc """
  Read one sample from the sensor.
  """
  @callback read_data(sensor_state :: term) ::
    {:ok, data :: term, new_sensor_state :: term}
    | {:error, reason :: term}
end
