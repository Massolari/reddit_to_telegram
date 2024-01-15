# Reddit to Telegram

This is a script that will send hot posts from a subreddit to a Telegram channel.

## Usage

> [!NOTE]  
> Requirements:
> - [Erlang](https://www.erlang.org/downloads)

1. Download the _script_ file from the [release page](https://github.com/Massolari/reddit_to_telegram/releases)
2. Follow the [setup](#setup) instructions
3. Add your Telegram bot as an admin to the channels you want to bridge
4. Give the _script_ permission to be executed
```bash
chmod +x ./reddit_to_telegram
```
6. Run the script:
```bash
./reddit_to_telegram
```

## Run from source

> [!NOTE]  
> Requirements:
> - [Erlang](https://www.erlang.org/downloads)
> - [Gleam](https://gleam.run/getting-started/installing/)

1. Clone this repository
2. Follow the [setup](#setup) instructions
3. Add your Telegram bot as an admin to the channels you want to bridge
4. Run the script:
```bash
gleam run
```

## Setup

1. Set the following environment variables:
```.env
# Your Reddit username and password
REDDIT_USERNAME=
REDDIT_PASSWORD=
# Reddit client ID and secret
# You can get these by creating an app on https://www.reddit.com/prefs/apps
REDDIT_CLIENT_ID=
REDDIT_CLIENT_SECRET=
# Telegram bot token
# You can get this by creating a bot with @BotFather
TELEGRAM_TOKEN=
```

2. Create the file `bridges.json` and fill in the values for the subreddits and channels you want to bridge:
```json
[
  {
    "subreddit": "golang",
    "channel": "@golang"
  },
  {
    "subreddit": "rust",
    "channel": "@rustlang"
  }
]
```

