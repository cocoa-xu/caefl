defmodule CAEFL.Environment do
  defmacro __using__(_opts) do
    quote do
      use GenServer
      @behaviour CAEFL.Environment

      def start_link(init_param, opts \\ []) do
        GenServer.start_link(__MODULE__, init_param, opts)
      end

      def start(init_param, opts \\ []) do
        GenServer.start(__MODULE__, init_param, opts)
      end

      @impl true
      def init(init_param) do
        {:ok, init_param}
      end

      @impl true
      def handle_call(:get_tags, _from, state) do
        with {:ok, sensors, new_state} <- __MODULE__.environment_sensors(state) do
          sensor_readings =
            Enum.map(sensors, fn sensor ->
              CAEFL.Sensor.read_data(sensor)
            end)
          sensor_tags =
             Enum.map(sensor_readings, fn sensor_reading ->
              transform(sensor_reading)
            end)
          tags =
            Enum.reduce(sensor_tags, %{}, fn sensor_tag, tags ->
              Map.merge(sensor_tag, tags, fn _, v1, _v2 -> v1 end)
            end)
          {:reply, tags, new_state}
        else
          {:error, err} -> {:error, err}
        end
      end
    end
  end

  @doc """
  Get current environment tags.
  """
  def get_tags(state) do
    GenServer.call(state, :get_tags)
  end

  @doc """
  Return a list of current available environment sensors.
  """
  @callback environment_sensors(state :: term) ::
    {:ok, sensors :: term, new_state :: term}
    | {:error, error :: term}

  @doc """
  Transform the data from a certain environment sensor to sematic/numerical tags.
  """
  @callback transform(sensor_readings :: term) :: map()
end
