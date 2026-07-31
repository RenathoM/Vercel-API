--[[
	ViewportRender.luau
	Modulo de Renderizacao 3D para o Catalogo de Planos de Fundo
	Gerencia o clone do avatar, dome do BackgroundStage_System e camera dentro da ViewportFrame
	IMPORTANTE: SurfaceGuis NAO renderizam em ViewportFrames. Usamos Decals em seu lugar.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ViewportRender = {}

-- Referencias internas
local viewportFrame: ViewportFrame
local worldModel: WorldModel
local viewportCamera: Camera
local characterClone: Model?
local stagePlane: Part?          -- 3D backdrop Part inside WorldModel
local isInitialized: boolean = false
local viewportChangedConnection: RBXScriptConnection?

-- Estado atual
local currentBackgroundAssetId: number? = nil
local isAvatarLoaded: boolean = false

-- Constantes de camera � avatar HRP em Y=3, camera enquadrando o corpo inteiro
local CAMERA_AVATAR_FOCUS = CFrame.new(Vector3.new(0, 4.5, 10), Vector3.new(0, 3, 0))
local CAMERA_BACKGROUND_FOCUS = CFrame.new(Vector3.new(0, 3, 13), Vector3.new(0, 3, -5))
local TWEEN_INFO = TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

--[[
	Inicializa o modulo com as referencias da ViewportFrame
	Clona o dome do BackgroundStage_System para dentro do WorldModel.
	Parametros: viewport (ViewportFrame) - a viewport do catalogo
]]
function ViewportRender.Initialize(viewport: ViewportFrame): ()
	viewportFrame = viewport
	worldModel = viewport:FindFirstChild("WorldModel") :: WorldModel

	-- Criar ou obter a ViewportCamera
	viewportCamera = viewport:FindFirstChild("ViewportCamera") :: Camera
	if not viewportCamera then
		viewportCamera = Instance.new("Camera")
		viewportCamera.Name = "ViewportCamera"
		viewportCamera.CFrame = CAMERA_AVATAR_FOCUS
		viewportCamera.Parent = viewport
	end

	viewport.CurrentCamera = viewportCamera

	-- Configurar iluminacao neutra (sem tonalidade azul)
	viewport.Ambient = Color3.fromRGB(180, 180, 180)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -1, -1)

-- Fundo solido escuro para o viewport (o StagePlane 3D sera o background visual)
	viewport.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	viewport.BackgroundTransparency = 0

	-- Criar o StagePlane 3D dentro do WorldModel:
	-- Um Part grande e plano posicionado atras do avatar, com um Decal para exibir o background.
	-- Decals funcionam corretamente em ViewportFrames ao contrario de SurfaceGuis.
	stagePlane = worldModel:FindFirstChild("StagePlane") :: Part
	if not stagePlane then
		stagePlane = Instance.new("Part")
		stagePlane.Name = "StagePlane"
		-- Plano grande o suficiente para preencher o campo de visao da camera
		-- Camera em Z=10 olhando para Z=0; plano em Z=-6 => distancia de 16u da camera
		-- Com FOV ~70 graus: largura visivel ~= 2*tan(35)*16 ~= 22u → usar 28x17 (16:9)
		stagePlane.Size = Vector3.new(28, 17, 0.05)
		stagePlane.CFrame = CFrame.new(0, 4.5, -6)
		stagePlane.Anchored = true
		stagePlane.CanCollide = false
		stagePlane.CastShadow = false
		stagePlane.Material = Enum.Material.SmoothPlastic
		stagePlane.Color = Color3.fromRGB(30, 30, 38) -- Cor neutra escura antes de aplicar background
		stagePlane.Parent = worldModel
	end

	isInitialized = true
end

--[[
	Cria o clone do avatar do jogador no WorldModel
	Parametros: player (Player) - o jogador local
]]
function ViewportRender.SetupAvatar(player: Player): ()
	if not isInitialized or not worldModel then return end

	local function onCharacterAdded(character: Model)
		-- Aguardar o character carregar completamente
		local hrp = character:WaitForChild("HumanoidRootPart", 15)
		local hum = character:WaitForChild("Humanoid", 15)
		if not hrp or not hum then return end

		-- Aguardar um frame extra para garantir que tudo carregou
		task.wait(0.5)

		-- Limpar clone anterior se existir
		if characterClone then
			characterClone.Parent = nil
			characterClone = nil
		end

		-- Clonar o character com protecao
		-- Importante: Characters tem Archivable = false por padrao, o que faz Clone() retornar nil
		-- Precisamos definir Archivable = true antes de clonar
		character.Archivable = true

		local cloneSuccess, cloneResult = pcall(function()
			return character:Clone()
		end)

		if not cloneSuccess or not cloneResult then
			-- Fallback: criar um manequim simples se o clone falhar
			characterClone = ViewportRender.CreateMannequin()
			if not characterClone then return end
		else
			characterClone = cloneResult
		end

		characterClone.Name = "CatalogAvatar"

		-- Tornar o clone nao fisico
		for _, part in characterClone:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
			-- Desativar scripts internos do character no viewport
			if part:IsA("LocalScript") or part:IsA("Script") then
				part.Disabled = true
			end
		end

		-- Posicionar E rotacionar o modelo inteiro usando PivotTo (move todas as partes)
		-- Rotacionar 180 graus para que o personagem olhe em direcao a camera (+Z)
		-- Personagens Roblox olham para -Z por padrao, entao 180 os faz olhar para +Z (camera)
		characterClone:PivotTo(CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(180), 0))

		characterClone.Parent = worldModel
		isAvatarLoaded = true

		-- Atualizar camera
		ViewportRender.FocusOnAvatar()
	end

	-- Conectar ao character atual e futuros
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
end

--[[
	Cria um manequim simples como fallback quando o clone do character falha
	Retorna: Model - o modelo do manequim
]]
function ViewportRender.CreateMannequin(): Model?
	if not worldModel then return nil end

	local model = Instance.new("Model")
	model.Name = "Mannequin"

	-- Cabeca
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Color = Color3.fromRGB(210, 180, 150)
	head.Material = Enum.Material.SmoothPlastic
	head.Anchored = true
	head.CanCollide = false
	head.CFrame = CFrame.new(0, 3.6, 0)
	head.Parent = model

	-- Torso
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.Color = Color3.fromRGB(0, 120, 215)
	torso.Material = Enum.Material.SmoothPlastic
	torso.Anchored = true
	torso.CanCollide = false
	torso.CFrame = CFrame.new(0, 2, 0)
	torso.Parent = model

	-- Braco Esquerdo
	local leftArm = Instance.new("Part")
	leftArm.Name = "Left Arm"
	leftArm.Size = Vector3.new(1, 2, 1)
	leftArm.Color = Color3.fromRGB(210, 180, 150)
	leftArm.Material = Enum.Material.SmoothPlastic
	leftArm.Anchored = true
	leftArm.CanCollide = false
	leftArm.CFrame = CFrame.new(-1.5, 2, 0)
	leftArm.Parent = model

	-- Braco Direito
	local rightArm = Instance.new("Part")
	rightArm.Name = "Right Arm"
	rightArm.Size = Vector3.new(1, 2, 1)
	rightArm.Color = Color3.fromRGB(210, 180, 150)
	rightArm.Material = Enum.Material.SmoothPlastic
	rightArm.Anchored = true
	rightArm.CanCollide = false
	rightArm.CFrame = CFrame.new(1.5, 2, 0)
	rightArm.Parent = model

	-- Perna Esquerda
	local leftLeg = Instance.new("Part")
	leftLeg.Name = "Left Leg"
	leftLeg.Size = Vector3.new(1, 2, 1)
	leftLeg.Color = Color3.fromRGB(40, 40, 50)
	leftLeg.Material = Enum.Material.SmoothPlastic
	leftLeg.Anchored = true
	leftLeg.CanCollide = false
	leftLeg.CFrame = CFrame.new(-0.5, 0, 0)
	leftLeg.Parent = model

	-- Perna Direita
	local rightLeg = Instance.new("Part")
	rightLeg.Name = "Right Leg"
	rightLeg.Size = Vector3.new(1, 2, 1)
	rightLeg.Color = Color3.fromRGB(40, 40, 50)
	rightLeg.Material = Enum.Material.SmoothPlastic
	rightLeg.Anchored = true
	rightLeg.CanCollide = false
	rightLeg.CFrame = CFrame.new(0.5, 0, 0)
	rightLeg.Parent = model

	-- HumanoidRootPart para rotacao
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(1, 2, 1)
	hrp.Transparency = 1
	hrp.CanCollide = false
	hrp.Anchored = true
	hrp.CFrame = CFrame.new(0, 2, 0)
	hrp.Parent = model

	-- Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.Parent = model

	model.PrimaryPart = hrp

	return model
end

-- (SetupBackgroundPlane removido � agora usamos ImageLabel atras do viewport)

--[[
	Aplica uma textura de fundo ao ImageLabel atras da ViewportFrame
	Parametros: assetId (number) - ID do asset de imagem
	            imageUrl (string?) - URL direta da imagem (opcional)
]]
function ViewportRender.ApplyBackground(assetId: number, imageUrl: string?): ()
	currentBackgroundAssetId = assetId

	-- Usar rbxthumb com resolucao maxima valida (700x700) para exibir o fundo
	-- Tamanhos validos para Asset: 150x150, 420x420, 700x700
	-- rbxthumb://type=Asset funciona com qualquer tipo de asset incluindo backgrounds
	local imageUrlToUse = imageUrl and imageUrl ~= "" and imageUrl or string.format("rbxthumb://type=Asset&id=%d&w=700&h=700", assetId)

	-- Se a URL passada usa 420x420, substituir por 700x700 para melhor qualidade
	imageUrlToUse = string.gsub(imageUrlToUse, "w=420&h=420", "w=700&h=700")

	-- Aplicar ao ImageLabel de fundo (atras da ViewportFrame) com transicao suave
	if backgroundImageLabel then
		local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

		local function doFadeIn()
			backgroundImageLabel.ImageTransparency = 1
			task.wait(0.1) -- Breve pausa para a imagem comecar a carregar
			local fadeIn = TweenService:Create(backgroundImageLabel, fadeInfo, {ImageTransparency = 0})
			fadeIn:Play()
		end

		if backgroundImageLabel.ImageTransparency < 1 then
			-- Fade out da imagem atual, depois carrega a nova com fade in
			local fadeOut = TweenService:Create(backgroundImageLabel, fadeInfo, {ImageTransparency = 1})
			fadeOut:Play()
			fadeOut.Completed:Connect(function()
				backgroundImageLabel.Image = imageUrlToUse
				task.spawn(doFadeIn)
			end)
		else
			-- Ja esta invisivel, apenas carrega e faz fade in
			backgroundImageLabel.Image = imageUrlToUse
			task.spawn(doFadeIn)
		end

		print(string.format("[ViewportRender] Background aplicado (resolucao nativa): %s", imageUrlToUse))
	else
		warn("[ViewportRender] backgroundImageLabel e nil � Initialize nao criou o ImageLabel")
	end
end

--[[
	Foca a camera no avatar com interpolacao suave
]]
function ViewportRender.FocusOnAvatar(): ()
	if not viewportCamera then return end

	local target = CAMERA_AVATAR_FOCUS
	local tween = TweenService:Create(viewportCamera, TWEEN_INFO, {CFrame = target})
	tween:Play()
end

--[[
	Foca a camera no plano de fundo com interpolacao suave
]]
function ViewportRender.FocusOnBackground(): ()
	if not viewportCamera then return end

	local target = CAMERA_BACKGROUND_FOCUS
	local tween = TweenService:Create(viewportCamera, TWEEN_INFO, {CFrame = target})
	tween:Play()
end

--[[
	Rotaciona o avatar clone suavemente
	Parametros: deltaAngle (number) - angulo de rotacao em radianos
]]
function ViewportRender.RotateAvatar(deltaAngle: number): ()
	if not characterClone then return end
	-- Usar PivotTo para rotacionar o modelo inteiro (nao apenas o HRP)
	local currentPivot = characterClone:GetPivot()
	characterClone:PivotTo(currentPivot * CFrame.Angles(0, deltaAngle, 0))
end

--[[
	Retorna o assetId do fundo atualmente aplicado
	Retorna: number?
]]
function ViewportRender.GetCurrentBackground(): number?
	return currentBackgroundAssetId
end

--[[
	Remove o fundo aplicado, voltando ao estado padrao
]]
function ViewportRender.RemoveBackground(): ()
	if stagePlane then
		local decal = stagePlane:FindFirstChildOfClass("Decal")
		if decal then
			local fadeOut = TweenService:Create(decal, TweenInfo.new(0.3, Enum.EasingStyle.Quart), {Transparency = 1})
			fadeOut:Play()
			fadeOut.Completed:Connect(function()
				if decal then decal.Texture = "" end
			end)
		end
	end

	currentBackgroundAssetId = nil
end

--[[
	Limpa todos os recursos criados pelo modulo
]]
function ViewportRender.Cleanup(): ()
	if viewportChangedConnection then
		viewportChangedConnection:Disconnect()
		viewportChangedConnection = nil
	end
	if characterClone then
		characterClone.Parent = nil
		characterClone = nil
	end
	if backgroundImageLabel then
		backgroundImageLabel.Parent = nil
		backgroundImageLabel = nil
	end
	isAvatarLoaded = false
	currentBackgroundAssetId = nil
end

return ViewportRender
