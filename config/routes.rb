Milly::Application.routes.draw do
  devise_for :users, controllers: { registrations: "users/registrations" }

  # Devise's account page, under a name of its own: /mon-compte gathers the password
  # change and the export instead of leaving them scattered in the navbar.
  devise_scope :user do
    get "mon-compte", to: "users/registrations#edit", as: :account
  end

  # L'accueil d'un utilisateur connecté est son tableau de bord ; la liste des bilans reste
  # à sa place, sur /balance_sheets, et garde son entrée dans la navbar.
  authenticated :user do
    root "dashboard#show", as: :authenticated_root
  end

  root "pages#home"

  resource :export, only: [:show]

  resources :properties
  # La fiche d'un actif ou d'un passif EST son formulaire : on y corrige chaque champ sur
  # place, et il n'y a donc pas de page « Modifier » derrière (voir assets#show).
  resources :assets, except: [:edit]
  resources :liabilities, except: [:edit]

  resources :balance_sheets do
    member do
      get :summary
    end
    resources :balance_sheet_assets, only: [:new, :create, :edit, :update, :destroy]
    resources :balance_sheet_liabilities, only: [:new, :create, :edit, :update, :destroy]
  end
end
