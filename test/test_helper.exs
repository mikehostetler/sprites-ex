default_exclude =
  case String.downcase(System.get_env("SPRITES_INCLUDE_LIVE", "")) do
    "1" -> []
    "true" -> []
    "yes" -> []
    _ -> [:live, :integration]
  end

ExUnit.start(exclude: default_exclude)
