var builder = WebApplication.CreateBuilder(args);

var frontOrigin = Environment.GetEnvironmentVariable("FRONT_ORIGIN") ?? "http://localhost:3000";

// Configuration des CORS pour autoriser les requêtes du front
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowFrontend", policy =>
    {
        policy.WithOrigins(frontOrigin)
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});

var app = builder.Build();

// Active le middleware CORS
app.UseCors("AllowFrontend");

var appEnvironment = Environment.GetEnvironmentVariable("APP_ENVIRONMENT") ?? "Production";
var appTitle = Environment.GetEnvironmentVariable("APP_TITLE") ?? "Hello Dockerignore !";

app.MapGet("/", () => Results.Json(new
{
    title = appTitle,
    environment = appEnvironment,
    message = "Le endpoint / fonctionne correctement !"
}));

app.MapGet("/health", () => Results.Ok(new { status = "up" }));

app.Run();
