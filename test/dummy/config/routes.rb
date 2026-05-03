Rails.application.routes.draw do
  mount ActiveJob::Notificare::Engine, at: "/notificare", as: :notificare

  get "/home", to: "home#index", as: :home

  resources :scaffold_demos, only: [:index, :show]
  resources :csv_imports, only: %i[index new create show]

  root to: "csv_imports#index"

  get "up" => "rails/health#show", as: :rails_health_check
end
