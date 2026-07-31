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
local backgroundImageLabel: ImageLabel?
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

	-- Tornar o fundo do viewport transparente para que o ImageLabel atras seja visivel
	viewport.BackgroundTransparency = 1

	-- Criar ImageLabel atras da ViewportFrame para exibir o fundo
	-- Decals e SurfaceGuis NAO funcionam bem em ViewportFrames, entao usamos
	-- um ImageLabel 2D atras do viewport transparente como fundo
	local parent = viewport.Parent
	if parent then
		backgroundImageLabel = parent:FindFirstChild("BackgroundImage") :: ImageLabel
		if not backgroundImageLabel then
			backgroundImageLabel = Instance.new("ImageLabel")
			backgroundImageLabel.Name = "BackgroundImage"
			-- Match the viewport's layout dynamically (recognized by script, not hardcoded)
			backgroundImageLabel.Size = viewport.Size
			backgroundImageLabel.Position = viewport.Position
			backgroundImageLabel.AnchorPoint = viewport.AnchorPoint
			backgroundImageLabel.BackgroundColor3 = parent.BackgroundColor3
			backgroundImageLabel.BackgroundTransparency = 0
			backgroundImageLabel.Image = ""
			backgroundImageLabel.ImageTransparency = 1
			backgroundImageLabel.ScaleType = Enum.ScaleType.Crop
			backgroundImageLabel.BorderSizePixel = 0
			backgroundImageLabel.ZIndex = math.max(0, viewport.ZIndex - 1)
			backgroundImageLabel.ClipsDescendants = true
			backgroundImageLabel.Parent = parent

			-- Copy UICorner from viewport so the background image matches the rounded shape
			local vpCorner = viewport:FindFirstChildOfClass("UICorner")
			if vpCorner then
				local bgCorner = Instance.new("UICorner")
				bgCorner.CornerRadius = vpCorner.CornerRadius
				bgCorner.Parent = backgroundImageLabel
			end

			-- Copy UIStroke from viewport for consistent border
			local vpStroke = viewport:FindFirstChildOfClass("UIStroke")
			if vpStroke then
				local bgStroke = Instance.new("UIStroke")
				bgStroke.Color = vpStroke.Color
				bgStroke.Thickness = vpStroke.Thickness
				bgStroke.Transparency = vpStroke.Transparency
				bgStroke.ApplyStrokeMode = vpStroke.ApplyStrokeMode
				bgStroke.Parent = backgroundImageLabel
			end

			-- Create edge gradient overlays for smooth transition from image to background
			-- These fade from the parent's background color (opaque at edges) to transparent (toward center)
			-- giving a soft vignette blend regardless of image orientation (horizontal or vertical)
			local gradientColor = parent.BackgroundColor3
			local fadeSize = 80 -- pixels of gradient fade at each edge

			-- Top edge fade
			local topFade = Instance.new("Frame")
			topFade.Name = "TopFade"
			topFade.Size = UDim2.new(1, 0, 0, fadeSize)
			topFade.Position = UDim2.new(0, 0, 0, 0)
			topFade.BackgroundColor3 = gradientColor
			topFade.BackgroundTransparency = 0
			topFade.BorderSizePixel = 0
			topFade.ZIndex = 1
			topFade.Parent = backgroundImageLabel
			local topGrad = Instance.new("UIGradient")
			topGrad.Rotation = 90
			topGrad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			topGrad.Parent = topFade

			-- Bottom edge fade
			local bottomFade = Instance.new("Frame")
			bottomFade.Name = "BottomFade"
			bottomFade.Size = UDim2.new(1, 0, 0, fadeSize)
			bottomFade.Position = UDim2.new(0, 0, 1, -fadeSize)
			bottomFade.BackgroundColor3 = gradientColor
			bottomFade.BackgroundTransparency = 0
			bottomFade.BorderSizePixel = 0
			bottomFade.ZIndex = 1
			bottomFade.Parent = backgroundImageLabel
			local bottomGrad = Instance.new("UIGradient")
			bottomGrad.Rotation = 90
			bottomGrad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0),
			})
			bottomGrad.Parent = bottomFade

			-- Left edge fade
			local leftFade = Instance.new("Frame")
			leftFade.Name = "LeftFade"
			leftFade.Size = UDim2.new(0, fadeSize, 1, 0)
			leftFade.Position = UDim2.new(0, 0, 0, 0)
			leftFade.BackgroundColor3 = gradientColor
			leftFade.BackgroundTransparency = 0
			leftFade.BorderSizePixel = 0
			leftFade.ZIndex = 1
			leftFade.Parent = backgroundImageLabel
			local leftGrad = Instance.new("UIGradient")
			leftGrad.Rotation = 0
			leftGrad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			leftGrad.Parent = leftFade

			-- Right edge fade
			local rightFade = Instance.new("Frame")
			rightFade.Name = "RightFade"
			rightFade.Size = UDim2.new(0, fadeSize, 1, 0)
			rightFade.Position = UDim2.new(1, -fadeSize, 0, 0)
			rightFade.BackgroundColor3 = gradientColor
			rightFade.BackgroundTransparency = 0
			rightFade.BorderSizePixel = 0
			rightFade.ZIndex = 1
			rightFade.Parent = backgroundImageLabel
			local rightGrad = Instance.new("UIGradient")
			rightGrad.Rotation = 0
			rightGrad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0),
			})
			rightGrad.Parent = rightFade

			-- Keep BackgroundImage synced with viewport when it resizes (e.g. fullscreen toggle)
			viewportChangedConnection = viewport.Changed:Connect(function(prop)
				if not backgroundImageLabel then return end
				if prop == "Size" then
					backgroundImageLabel.Size = viewport.Size
				elseif prop == "Position" then
					backgroundImageLabel.Position = viewport.Position
				elseif prop == "AnchorPoint" then
					backgroundImageLabel.AnchorPoint = viewport.AnchorPoint
				end
			end)
		else
			-- Update existing BackgroundImage to use new dynamic settings
			backgroundImageLabel.Size = viewport.Size
			backgroundImageLabel.Position = viewport.Position
			backgroundImageLabel.AnchorPoint = viewport.AnchorPoint
			backgroundImageLabel.ScaleType = Enum.ScaleType.Crop
			backgroundImageLabel.ClipsDescendants = true
		end
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
	if backgroundImageLabel then
		-- Fade out suave antes de remover a imagem
		local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		local fadeOut = TweenService:Create(backgroundImageLabel, fadeInfo, {ImageTransparency = 1})
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			if backgroundImageLabel then
				backgroundImageLabel.Image = ""
			end
		end)
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
