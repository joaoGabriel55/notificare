ActiveJob::Notificare::Engine.routes.draw do
  root to: "executions#index"
  resources :executions, only: [ :index, :show ]

  resources :notifications, only: [] do
    member do
      patch :read
      patch :dismiss
    end
  end

  delete "notifications", to: "notifications#clear", as: :clear_notifications
end
