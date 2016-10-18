{-# LANGUAGE OverloadedStrings #-}

module Main where

import           Control.Lens
import           Control.Monad.Trans.Class
import           Data.Aeson
import           Data.Maybe                  (fromJust, fromMaybe)
import           Data.Monoid                 ((<>))
import qualified Data.Text as T
import           Data.Yaml                   (decodeFile)
import           GitlabApi.Data
import           Network.Connection          (TLSSettings (..))
import           Network.HTTP.Client.TLS     (mkManagerSettings)
import           Network.HTTP.Types.Status   (ok200)
import           Network.URL                 (URL, importURL, exportURL)
import qualified Network.Wreq as W
import           Web.Scotty

import           MattermostBot.Data

main :: IO ()
main = scotty 9666 $ do
  post "/gitlab/webhooks" $ do
    cfg <- lift botConfig
    lift $ print $ show cfg
    hdr <- header "X-Gitlab-Event"
    evt <- jsonData :: ActionM GitlabEvent
    lift $ print $ show $ toJSON $ whToSlack cfg evt
    lift $ W.postWith opts (exportURL $ _botConfigMattermostIncoming cfg) (toJSON $ whToSlack cfg evt)
    lift $ print $ show $ encode $ whToSlack cfg evt
    status ok200
  post "/gitlab/systemhooks" $ do
    cfg <- lift botConfig
    lift $ print $ show cfg
    hdr <- header "X-Gitlab-Event"
    evt <- jsonData :: ActionM SystemHook
    lift $ print $ show $ toJSON $ shToSlack cfg evt
    lift $ W.postWith opts (exportURL $ _botConfigMattermostIncoming cfg) (toJSON $ shToSlack cfg evt)
    lift $ print $ show $ encode $ shToSlack cfg evt
    status ok200

-- | disable tls
opts = W.defaults & W.manager .~ Left (mkManagerSettings (TLSSettingsSimple True False False) Nothing)

botConfig :: IO BotConfig
botConfig = fromMaybe defaultCfg <$> readCfg

defaultCfg :: BotConfig
defaultCfg = BotConfig "TownsSquare" "λmatterbot" ":ghost:" $ fromJust $ importURL "mattermostIncoming"

readCfg :: IO (Maybe BotConfig)
readCfg = decodeFile "./botconfig.yaml"

whToSlack :: BotConfig -> GitlabEvent -> SlackIncoming
whToSlack c (WHPushEvent _ _ _ _ _ _ userName _ _ _ _ project commits _) =
  toIncoming c (
  userName <> " pushed \n"
  <> T.unlines (pushCommitToMarkDown <$> commits)
  <> "\n to " <> _projectName project)
whToSlack c (IssueEvent _ user _ _ _ _) = toIncoming c (_userUserName user <> " modified issue")
whToSlack c (PipelineEvent _ _ user project commit builds) =
  toIncoming c ("builds initiated by " <>  _userUserName user
  <> " in project " <> _pipelineEventProjectName project
  <> "\n" <> T.unlines (buildToMarkDown <$> builds))

shToSlack :: BotConfig -> SystemHook-> SlackIncoming
shToSlack c (SHPushEvent _ _ _ _ _ userName _ _ _ _ project commits _) =
  toIncoming c (
  userName <> " pushed \n"
  <> T.unlines (pushCommitToMarkDown <$> commits)
  <> "\n to " <> _projectName project)
shToSlack c (ProjectCreated _ _ _ name _ ownerName _ pathWithNamespace id _) =
  toIncoming c (":new: " <> ownerName <> " created a new project " <> name <> " " <> parenthesize  pathWithNamespace)
shToSlack c (ProjectDestroyed _ _ _ name _ ownerName _ pathWithNamespace _ _) =
  toIncoming c (":x: project " <> name <> " deleted " <> parenthesize pathWithNamespace)
shToSlack c (ProjectRenamed _ _ _ name _ ownerName _ pathWithNamespace pathWithNamespaceOld _ _) =
  toIncoming c (":pencil: project " <> name <> " renamed " <> parenthesize (pathWithNamespaceOld <> " -> " <> pathWithNamespace))

pushCommitToMarkDown :: Commit -> T.Text
pushCommitToMarkDown c = "- " <> "[" <> _commitMessage c <> "]" <> "(" <> T.pack (exportURL $ _commitUrl c) <> ")"

buildToMarkDown :: Build -> T.Text
buildToMarkDown b = "id: " <> T.pack (show $ _buildId b) <> " status: " <> _buildStatus b

toIncoming :: BotConfig -> T.Text -> SlackIncoming
toIncoming c t = SlackIncoming t (_botConfigChannel c) (_botConfigUsername c) (_botConfigIconEmoij c)

parenthesize :: T.Text -> T.Text
parenthesize inner = "(" <> inner <> ")"
