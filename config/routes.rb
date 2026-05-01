ActiveJob::Notificare::Engine.routes.draw do
  resources :notifications, only: [] do
    member do
      patch :read
      patch :dismiss
    end
  end

  delete "notifications", to: "notifications#clear", as: :clear_notifications
end
