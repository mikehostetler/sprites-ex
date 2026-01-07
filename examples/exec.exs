# Example: Execute Command
# Endpoint: WSS /v1/sprites/{name}/exec

token = System.get_env("SPRITE_TOKEN")
sprite_name = System.get_env("SPRITE_NAME")

client = Sprites.new(token)
sprite = Sprites.sprite(client, sprite_name)

{output, _exit_code} = Sprites.cmd(sprite, "echo", ["hello", "world"])

IO.write(output)
