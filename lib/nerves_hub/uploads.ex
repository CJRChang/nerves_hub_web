defmodule NervesHub.Uploads do
  @callback delete(key :: String.t()) :: :ok | {:error, any()}

  @callback upload(file_path :: String.t(), key :: String.t(), opts :: Keyword.t()) ::
              :ok | {:error, any()}

  @callback url(key :: String.t(), opts :: Keyword.t()) :: String.t()

  def backend() do
    Application.get_env(:nerves_hub, __MODULE__)[:backend]
  end

  def upload(file, key, opts \\ []) do
    backend().upload(file, key, opts)
  end

  def url(key, opts \\ []) do
    backend().url(key, opts)
  end

  def delete(key) do
    backend().delete(key)
  end
end

defmodule NervesHub.Uploads.File do
  @behaviour NervesHub.Uploads

  def local_path() do
    Application.get_env(:nerves_hub, __MODULE__)[:local_path]
  end

  @impl NervesHub.Uploads
  def delete(key) do
    path = Path.join(local_path(), key)
    :ok = File.rm(path)

    :ok
  end

  @impl NervesHub.Uploads
  def upload(file_path, key, _opts) do
    path = Path.join(local_path(), key)

    dirname = Path.dirname(path)
    _ = File.mkdir_p(dirname)

    case File.copy(file_path, path) do
      {:ok, _} ->
        :ok

      _ ->
        {:error, :uploading}
    end
  end

  @impl NervesHub.Uploads
  def url("/" <> key, opts), do: url(key, opts)

  def url(key, _opts) do
    config = Application.get_env(:nerves_hub, NervesHubWeb.Endpoint)[:url]
    uri = URI.parse("/uploads/#{key}")

    uri = %{
      uri
      | host: config[:host],
        port: config[:port],
        scheme: config[:scheme]
    }

    URI.to_string(uri)
  end
end

defmodule NervesHub.Uploads.S3 do
  @behaviour NervesHub.Uploads

  alias ExAws.S3

  def bucket() do
    Application.get_env(:nerves_hub, __MODULE__)[:bucket]
  end

  @impl NervesHub.Uploads
  def delete(key) do
    {:ok, _} =
      bucket()
      |> S3.delete_object(key)
      |> ExAws.request()

    :ok
  end

  @impl NervesHub.Uploads
  def upload(file_path, key, opts) do
    bucket()
    |> S3.put_object(key, File.read!(file_path), Keyword.get(opts, :meta, []))
    |> ExAws.request!()

    :ok
  end

  @impl NervesHub.Uploads
  def url(key, opts) do
    case Keyword.has_key?(opts, :signed) do
      true ->
        config = ExAws.Config.new(:s3)
        {:ok, url} = S3.presigned_url(config, :get, bucket(), key, opts[:signed])
        url

      false ->
        "https://s3.amazonaws.com/#{bucket()}#{key}"
    end
  end
end

defmodule NervesHub.Uploads.GCS do
  @behaviour NervesHub.Uploads

  alias GoogleApi.Storage.V1.Api.Objects
  alias GoogleApi.Storage.V1.Connection

  def bucket() do
    Application.get_env(:nerves_hub, __MODULE__)[:bucket]
  end

  @impl NervesHub.Uploads
  def delete(key) do
    conn = get_connection()

    try do
      {:ok, _} = Objects.storage_objects_delete(
        conn,
        bucket(),
        key
      )
      :ok
    rescue
      e -> {:error, e}
    end
  end

  @impl NervesHub.Uploads
  def upload(file_path, key, opts) do
    conn = get_connection()

    try do
      {:ok, _object} = Objects.storage_objects_insert_simple(
        conn,
        bucket(),
        "multipart",
        %{name: key, metadata: Keyword.get(opts, :meta, %{})},
        File.read!(file_path)
      )
      :ok
    rescue
      e -> {:error, e}
    end
  end

  @impl NervesHub.Uploads
  def url(key, opts) do
    case Keyword.has_key?(opts, :signed) do
      true ->
        gcs_client = cond do
          !is_nil(System.get_env("GOOGLE_APPLICATION_CREDENTIALS")) ->
            GcsSignedUrl.Client.load_from_file(System.fetch_env!("GOOGLE_APPLICATION_CREDENTIALS"))
          !is_nil(System.get_env("GOOGLE_APPLICATION_CREDENTIALS_JSON")) ->
            credentials = System.fetch_env!("GOOGLE_APPLICATION_CREDENTIALS_JSON")
                          |> Jason.decode!()
            GcsSignedUrl.Client.load(credentials)
          true -> nil
        end
        GcsSignedUrl.generate_v4(
          gcs_client,
          bucket(),
          key,
          opts[:signed]
        )

      false ->
        "https://storage.googleapis.com/#{bucket()}/#{key}"
    end
  end

  defp get_connection() do
    token = Goth.fetch!(NervesHub.Goth)
    Connection.new(token.token)
  end
end
