use anyhow::Result;
use reqwest::Client;
use serde::Deserialize;
use crate::api::authed_get;
use crate::models::{Project, Task};

#[derive(Deserialize)]
struct ProjectResponse {
    id: String,
    name: String,
    description: Option<String>,
    tasks: Option<Vec<TaskResponse>>,
}

#[derive(Deserialize)]
struct TaskResponse {
    id: String,
    name: String,
}

pub async fn get_assigned(client: &Client, _tenant_id: &str) -> Result<Vec<Project>> {
    let res = authed_get(client, "/projects/assigned").await?;
    let projects: Vec<ProjectResponse> = res.json().await?;
    Ok(projects.into_iter().map(|p| Project {
        id: p.id.parse().unwrap_or_default(),
        name: p.name.clone(),
        description: p.description,
        tasks: p.tasks.unwrap_or_default().into_iter().map(|t| Task {
            task_id: t.id.parse().unwrap_or_default(),
            project_id: p.id.parse().unwrap_or_default(),
            task_name: t.name,
            project_name: p.name.clone(),
        }).collect(),
    }).collect())
}

