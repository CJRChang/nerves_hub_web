defmodule NervesHub.Devices.DeviceHealth do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.Device

  @type t :: %__MODULE__{}
  @required_params [:device_id, :data]
  @optional_params [:status, :status_reasons]

  schema "device_health" do
    belongs_to(:device, Device)
    field(:data, :map)

    field(:status, Ecto.Enum,
      values: [:unknown, :healthy, :warning, :unhealthy],
      default: :unknown
    )

    field(:status_reasons, :map)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def save(params) do
    %__MODULE__{}
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
  end
end
