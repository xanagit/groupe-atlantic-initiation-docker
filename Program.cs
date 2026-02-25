var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => Results.Json(new
{
    title = "Hello Multi-Stage !",
    message = "Le endpoint / fonctionne correctement !"
}));

app.MapGet("/health", () => Results.Ok(new { status = "up" }));

app.Run();
