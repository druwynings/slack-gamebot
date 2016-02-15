module Api
  module Endpoints
    class TeamsEndpoint < Grape::API
      format :json
      helpers Api::Helpers::CursorHelpers
      helpers Api::Helpers::SortHelpers
      helpers Api::Helpers::PaginationParameters

      namespace :teams do
        desc 'Get a team.'
        params do
          requires :id, type: String, desc: 'Team ID.'
        end
        get ':id' do
          team = Team.find(params[:id]) || error!('Not Found', 404)
          error!('Not Found', 404) unless team.api?
          present team, with: Api::Presenters::TeamPresenter
        end

        desc 'Get all the teams.'
        params do
          optional :active, type: Boolean, desc: 'Return active teams only.'
          optional :game, type: String, desc: 'Return teams for a given game by name.'
          optional :game_id, type: String, desc: 'Return teams for a given game by ID.'
          mutually_exclusive :game, :game_id
          use :pagination
        end
        sort Team::SORT_ORDERS
        get do
          game = Game.find(params[:game_id]) if params.key?(:game_id)
          game ||= Game.where(name: params[:game]) if params.key?(:game)
          teams = game ? game.teams : Team.all
          teams = teams.api
          teams = teams.active if params[:active]
          teams = paginate_and_sort_by_cursor(teams, default_sort_order: '-_id')
          present teams, with: Api::Presenters::TeamsPresenter
        end

        desc 'Create a team using an OAuth token.'
        params do
          requires :code, type: String
          optional :game, type: String
          optional :game_id, type: String
          exactly_one_of :game, :game_id
        end
        post do
          game = Game.find(params[:game_id]) if params.key?(:game_id)
          game ||= Game.where(name: params[:game]).first if params.key?(:game)
          error!('Game Not Found', 404) unless game

          client = Slack::Web::Client.new

          rc = client.oauth_access(
            client_id: game.client_id,
            client_secret: game.client_secret,
            code: params[:code]
          )

          team = Team.where(token: rc['bot']['bot_access_token']).first
          team ||= Team.where(team_id: rc['team_id'], game: game).first
          if team && !team.active?
            error!('Invalid Game', 400) unless team.game == game
            team.activate!
          elsif team
            error!('Invalid Game', 400) unless team.game == game
            fail "Team #{team.name} is already registered."
          else
            team = Team.create!(
              game: game,
              aliases: game.aliases,
              token: rc['bot']['bot_access_token'],
              team_id: rc['team_id'],
              name: rc['team_name']
            )
          end

          SlackGamebot::Service.start!(team)
          present team, with: Api::Presenters::TeamPresenter
        end
      end
    end
  end
end
