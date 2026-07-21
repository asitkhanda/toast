using System.Text.Json;
using Toast.Core.Services;

namespace Toast.Services;

public sealed class JsonPreferencesStore : IPreferencesStore
{
    private readonly string _path;
    private readonly object _gate = new();
    private Dictionary<string, JsonElement> _data = new();

    public JsonPreferencesStore()
    {
        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Toast");
        Directory.CreateDirectory(dir);
        _path = Path.Combine(dir, "preferences.json");
        Load();
    }

    public bool GetBool(string key, bool defaultValue)
    {
        lock (_gate)
        {
            if (!_data.TryGetValue(key, out var el))
            {
                return defaultValue;
            }

            return el.ValueKind switch
            {
                JsonValueKind.True => true,
                JsonValueKind.False => false,
                _ => defaultValue,
            };
        }
    }

    public void SetBool(string key, bool value)
    {
        lock (_gate)
        {
            _data[key] = JsonSerializer.SerializeToElement(value);
            Save();
        }
    }

    public string? GetString(string key)
    {
        lock (_gate)
        {
            if (!_data.TryGetValue(key, out var el) || el.ValueKind != JsonValueKind.String)
            {
                return null;
            }

            return el.GetString();
        }
    }

    public void SetString(string key, string? value)
    {
        lock (_gate)
        {
            if (value is null)
            {
                _data.Remove(key);
            }
            else
            {
                _data[key] = JsonSerializer.SerializeToElement(value);
            }

            Save();
        }
    }

    public T? GetJson<T>(string key)
    {
        lock (_gate)
        {
            if (!_data.TryGetValue(key, out var el))
            {
                return default;
            }

            return el.Deserialize<T>();
        }
    }

    public void SetJson<T>(string key, T? value)
    {
        lock (_gate)
        {
            if (value is null)
            {
                _data.Remove(key);
            }
            else
            {
                _data[key] = JsonSerializer.SerializeToElement(value);
            }

            Save();
        }
    }

    private void Load()
    {
        if (!File.Exists(_path))
        {
            return;
        }

        try
        {
            var json = File.ReadAllText(_path);
            _data = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(json) ?? new();
        }
        catch
        {
            _data = new();
        }
    }

    private void Save()
    {
        var json = JsonSerializer.Serialize(_data, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(_path, json);
    }
}
