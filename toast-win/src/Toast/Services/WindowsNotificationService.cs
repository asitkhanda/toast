using Toast.Core.Services;

namespace Toast.Services;

public sealed class WindowsNotificationService : INotificationService
{
    public event EventHandler<(string Title, string Body)>? NotificationRequested;

    public Task RequestAuthorizationAsync() => Task.CompletedTask;

    public Task NotifyAsync(string title, string body)
    {
        NotificationRequested?.Invoke(this, (title, body));
        return Task.CompletedTask;
    }
}
