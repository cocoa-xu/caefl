defmodule Caefl do
  @moduledoc """
  Documentation for `Caefl`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Caefl.hello()
      :world

  """
  def run_test(opts \\ []) do
    default_backend = opts[:default_backend] || Torchx.Backend
    Nx.default_backend(default_backend)

    {train_images, train_labels} = Scidata.MNIST.download()

    {images_binary, images_type, images_shape} = train_images
    train_images_binary =
      images_binary
      |> Nx.from_binary(images_type)
      |> Nx.reshape(images_shape)
      |> Nx.divide(255)

    {labels_binary, labels_type, _shape} = train_labels
    train_labels_onehot =
      labels_binary
      |> Nx.from_binary(labels_type)
      |> Nx.new_axis(-1)
      |> Nx.equal(Nx.tensor(Enum.to_list(0..9)))

    {train_images_binary, train_labels_onehot}
  end
end
