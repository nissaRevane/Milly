Milly::Application.routes.draw do
  devise_for :users

  authenticated :user do
    root "balance_sheets#index", as: :authenticated_root
  end

  root "pages#home"

  resources :assets, except: [:show]
  resources :liabilities, except: [:show]

  resources :balance_sheets do
    member do
      get :summary
    end
    resources :balance_sheet_assets, only: [:new, :create, :edit, :update, :destroy]
    resources :balance_sheet_liabilities, only: [:new, :create, :edit, :update, :destroy]
  end
end
