Milly::Application.routes.draw do
  devise_for :users, controllers: { registrations: "users/registrations" }

  # Devise's account page, under a name of its own: /mon-compte gathers the password
  # change and the export instead of leaving them scattered in the navbar.
  devise_scope :user do
    get "mon-compte", to: "users/registrations#edit", as: :account
  end

  authenticated :user do
    root "balance_sheets#index", as: :authenticated_root
  end

  root "pages#home"

  resource :export, only: [:show]

  resources :properties
  resources :assets, except: [:show]
  resources :liabilities

  resources :balance_sheets do
    member do
      get :summary
    end
    resources :balance_sheet_assets, only: [:new, :create, :edit, :update, :destroy]
    resources :balance_sheet_liabilities, only: [:new, :create, :edit, :update, :destroy]
  end
end
