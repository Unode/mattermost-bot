{-# LANGUAGE OverloadedStrings #-}

module Main where

import           Control.Lens
import           Control.Monad.Trans.Class
import           Data.Aeson
import           Data.Maybe                  (fromJust, fromMaybe)
import           Data.Monoid                 ((<>))
import qualified Data.Text as T
import           Data.Yaml                   (decodeFile)
import           GitlabHooks.Data.Types
import           Network.Connection          (TLSSettings (..))
import           Network.HTTP.Client.TLS     (mkManagerSettings)
import           Network.HTTP.Types.Status   (ok200)
import           Network.URL                 (URL, importURL, exportURL)
import qualified Network.Wreq as W
import           Web.Scotty

import           MattermostBot.Data

main :: IO ()
main = scotty 3000 $
  post "/triggerci" $ do
    hdr <- header "X-Gitlab-Event"
    evt <- jsonData :: ActionM GitlabEvent
    cfg <- lift botConfig
    lift $ print $ show cfg
    lift $ W.postWith opts (exportURL $ _botConfigMattermostIncoming cfg) (toJSON $ toSlack cfg evt)
    lift $ print $ show $ encode $ toSlack cfg evt
    status ok200

-- | disable tls
opts = W.defaults & W.manager .~ Left (mkManagerSettings (TLSSettingsSimple True False False) Nothing)

botConfig :: IO BotConfig
botConfig = fromMaybe defaultCfg <$> readCfg

defaultCfg :: BotConfig
defaultCfg = BotConfig "TownsSquare" "λmatterbot" ":ghost:" $ fromJust $ importURL "mattermostIncoming"

readCfg :: IO (Maybe BotConfig)
readCfg = decodeFile "./botconfig.yaml"

toSlack :: BotConfig -> GitlabEvent -> SlackIncoming
toSlack c (PushEvent _ _ _ _ _ _ userName _ _ _ _ project commits _) =
  toIncoming c (
  userName <> " pushed \n"
  <> T.unlines (pushCommitToMarkDown <$> commits)
  <> "\n to " <> _projectName project)
toSlack c (IssueEvent _ user _ _ _ _) = toIncoming c (_userUserName user <> " modified issue")

pushCommitToMarkDown :: Commit -> T.Text
pushCommitToMarkDown c = "- " <> "[" <> _commitMessage c <> "]" <> "(" <> T.pack (exportURL $ _commitUrl c) <> ")"

toIncoming :: BotConfig -> T.Text -> SlackIncoming
toIncoming c t = SlackIncoming t (_botConfigChannel c) (_botConfigUsername c) (_botConfigIconEmoij c)
