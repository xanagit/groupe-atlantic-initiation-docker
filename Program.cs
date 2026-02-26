var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// Récupérer l'environnement et le titre 
// dans les variables d'environnement (APP_ENVIRONMENT et APP_TITLE)
var appEnvironment = Environment.GetEnvironmentVariable("APP_ENVIRONMENT") ?? "Production";
var appTitle = Environment.GetEnvironmentVariable("APP_TITLE") ?? "Hello ENV & ARG !";

app.MapGet("/", () => Results.Json(new
{
    title = appTitle,
    environment = appEnvironment,
    message = "Le endpoint / fonctionne correctement !"
}));

app.MapGet("/health", () => Results.Ok(new { status = "up" }));

app.Run();
