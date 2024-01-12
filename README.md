# Reddit to Telegram

This is a script that will send hot posts from a subreddit to a Telegram channel.

## Usage

1. Clone this repository
2. Copy the `.env.example` file to `.env` and fill in the values:
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
3. Copy the `bridges.example.json` file to `bridges.json` and fill in the values for the subreddits and channels you want to bridge:
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
4. Add your Telegram bot as an admin to the channels you want to bridge
5. Run the script: `gleam run`
