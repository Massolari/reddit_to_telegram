![Docker Build](https://github.com/Massolari/reddit_to_telegram/actions/workflows/docker-image.yml/badge.svg)
![Tests](https://github.com/Massolari/reddit_to_telegram/actions/workflows/test.yml/badge.svg)

# Reddit to Telegram

This is a script that will send hot/new/top/rising posts from a subreddit to a Telegram channel.

## Usage

### From docker

> [!NOTE]  
> Requirements:
> - [Docker](https://docs.docker.com/engine/install/)

1. Follow the [setup](#setup) instructions
2. Add your Telegram bot as an admin to the channels you want to bridge
3. Run the image replacing the volumes with the paths to your files:
```bash
docker run \
  --volume /path/to/.env:/app/.env \
  --volume /path/to/bridges.json:/app/bridges.json \
  --volume /path/to/db:/app/db \
  massolari/reddit-to-telegram:latest
```

> [!TIP]
> You can create a shell script with the above command and run it as a cron job.


### From source

> [!NOTE]  
> Requirements:
> - [Erlang](https://www.erlang.org/downloads)
> - [Gleam](https://gleam.run/getting-started/installing/)
> - [ffmpeg](https://ffmpeg.org/download.html)

1. Clone this repository
2. Follow the [setup](#setup) instructions
3. Add your Telegram bot as an admin to the channels you want to bridge
4. Run the script:
```bash
gleam run
```

## Setup

1. Create a `.env` file and fill in the values (you can use `.env.example` as a template):
```.env
# Your Reddit username and password
REDDIT_USERNAME=
REDDIT_PASSWORD=
# Reddit client ID and secret
# You can get these by creating an app on https://www.reddit.com/prefs/apps
# Make sure to set the app type to "script"
REDDIT_CLIENT_ID=
REDDIT_CLIENT_SECRET=
# Telegram bot token
# You can get this by creating a bot with @BotFather
TELEGRAM_TOKEN=
```

> [!IMPORTANT]
> The comments (lines starting with `#`) are for documentation purposes only and **must not** be included in the `.env` file. Otherwise, the values will not be loaded.

2. Create the file `bridges.json` and fill in the values for the subreddits and channels you want to bridge (you can use `bridges.example.json` as a template):
```json
[
  {
    "subreddit": "gleamlang",
    "reddit_sort": "hot",
    "telegram_channel": "@r_gleam"
  }
]
```

| Field | Description |
| --- | --- |
| `subreddit` | The subreddit to bridge in. It's the last part of the URL, for example, for the URL https://www.reddit.com/r/gleamlang the subreddit is `gleamlang` |
| `reddit_sort` | The sorting method to use when fetching posts from Reddit. Available options are `hot`, `new`, `top` and `rising` |
| `telegram_channel` | The Telegram channel to send the posts to. It's the channel username with the `@` prefix, for example, for the URL https://t.me/r_gleam the channel is `@r_gleam` |

