var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => new
{
    title = "Hello Sécurité !",
    user = Environment.UserName,
    message = "Le endpoint / fonctionne correctement !"
});

app.MapGet("/health", () => new { status = "up" });

app.Run();
