//
//  GameplayLayer.m
//  WonkyBird
//
//  Created by Cam Saul on 2/23/14.
//  Copyright (c) 2014 LuckyBird, Inc. All rights reserved.
//

#include <random>

#import "GameplayLayer.h"
#import "GameSprite.h"
#import "Toucan.h"
#import "Pipe.h"
#import "GameManager.h"

static const float kToucanMenuRandVelocity = 10.0f; ///< Apply +/- this amount to toucan's y velocity in main menu
static auto Rand = std::bind (std::uniform_real_distribution<float>(0.0f, 1.0f), std::default_random_engine()); // nice random number between 0.0f and 1.0f

static const int GroundHeight = 125;
static const int kMaxNumPipes = 1;

@interface GameplayLayer ()
@property (nonatomic, strong) Toucan *toucan;
@property (nonatomic, strong) GameSprite *ground;
@property (nonatomic, strong) NSMutableArray *walls;
@property (nonatomic, strong) NSMutableArray *pipes;
@end

@implementation GameplayLayer

- (instancetype)init {
	if (self = [super initWithTextureAtlasNamed:@"Textures"]) {
		srandom((int)time(NULL));
		
		self.toucan = [[Toucan alloc] init];
		self.toucan.position = ccp(ScreenWidth() / 2.0f, ScreenHeight() * kToucanMenuHeight);
		[self.spriteBatchNode addChild:self.toucan];
		[self.toucan.item addToWorld:self.world];
		
		// add the ground
		self.ground = [[GameSprite alloc] init];
		self.ground.item.bodyDef->type = b2_staticBody;
		self.ground.position = CGPointMake(ScreenWidth() / 2.0f, GroundHeight / 2);
		self.ground.contentSize = CGSizeMake(ScreenWidth() * 2 /* extend out past edges a bit */, GroundHeight);
		self.ground.item.fixtureDef->density = 0.0f;
		[self.ground.item addToWorld:self.world];
		
		// add the "walls"
		self.walls = [NSMutableArray array];
		
		auto makeWall = [&](float x, float y, float width, float height) {
			GameSprite *wall = [[GameSprite alloc] init];
			wall.item.bodyDef->type = b2_staticBody;
			wall.position = CGPointMake(x, y);
			wall.contentSize = CGSizeMake(width, height);
			wall.item.fixtureDef->density = 0.0f;
			wall.item.fixtureDef->restitution = 0.4f;
			[wall.item addToWorld:self.world];
			[self.walls addObject:wall];
		};
		makeWall(ScreenWidth() / 2, ScreenHeight() - 2, ScreenWidth() * 2, 4); // roof
//		makeWall(-70 /* enough to move pipe offscreen */, ScreenHeight() / 2, 4, ScreenHeight()); // left wall
//		makeWall(ScreenWidth() + 2, ScreenHeight() / 2, 4, ScreenHeight()); // right wall
				
		self.touchEnabled = YES;
	}
	return self;
}

- (void)addPipeOfSize:(int)pipeSize {
	Pipe *p = [Pipe pipeOfSize:pipeSize];
	p.position = CGPointMake(ScreenWidth(), p.contentSize.height / 2 + GroundHeight);
	[self addChild:p.layer];
	[p.item addToWorld:self.world];
	[self.pipes addObject:p];
}

- (void)addRandomPipeIfNeeded {
	if (self.pipes.count < kMaxNumPipes) {
		[self addPipeOfSize:(random() % 4) + 2];
	}
}

- (void)registerWithTouchDispatcher {
	[[[CCDirector sharedDirector] touchDispatcher] addTargetedDelegate:self priority:0 swallowsTouches:YES];
}

- (void)update:(ccTime)delta {
	if (!GStateIsActive()) {
		const float randVel = (Rand() * 2 * kToucanMenuRandVelocity) - kToucanMenuRandVelocity;
		const float heightCorrectionVel = ((ScreenHeight() * kToucanMenuHeight) / kPTMRatio) - self.toucan.item.positionForBox2D.y; ///< add neccessary velocity to keep toucan around the right y spot during flapping
		
		static float AntiGravityAmount = Rand(); // amount of gravity to apply on home screen will be random
		const float newYVel = (-kGravityVelocity * AntiGravityAmount) + heightCorrectionVel + randVel;
		self.toucan.item.body->ApplyForceToCenter({Rand(), newYVel}, true);
//		
		// randomly apply force to toucan
		if (Rand() < (1.0f / 1000.0f)) {
			NSLog(@"TONS OF FORCE!");
			self.toucan.item.body->ApplyForceToCenter({0, 100}, true);
		}
		
		// randomly apply force to toucan
		if (Rand() < (1.0f / 100.0f)) {
			NSLog(@"TONS OF FORCE!");
			self.toucan.item.body->ApplyForceToCenter({0, 10}, true);
		}
	}
	
	[super update:delta];
	
	CCArray *gameObjects = self.spriteBatchNode.children; // TODO - this should be iterated in a thread safe manner ?
	for (GameSprite *sprite in gameObjects) {
		[sprite updateStateWithDeltaTime:delta andListOfGameObjects:gameObjects];
	}
	
	if (!GStateIsActive()) return; // don't add pipes unless we're active
	
	for (Pipe *p in self.pipes.copy) {
		if (p.position.x < -p.contentSize.width / 2) {
			[self.pipes removeObject:p];
			[self removeChild:p.layer cleanup:YES];
			dispatch_async(dispatch_get_main_queue(), ^{
				[self addRandomPipeIfNeeded];
			});
		} else {
			p.item.body->SetLinearVelocity({-1.0f, 0});
		}
	}
}

- (BOOL)ccTouchBegan:(UITouch *)touch withEvent:(UIEvent *)event {
	if (!GStateIsActive()) {
		return NO;
	}
	
	if (self.toucan.state != ToucanStateDead) {
		self.toucan.item.body->SetAwake(true);
		
		const float yVelocity = self.toucan.item.body->GetLinearVelocity().y;
		const float YVelocityBase = 50 + rand() % 50;
		const float yAmount = yVelocity > 1 ? (YVelocityBase / yVelocity) : YVelocityBase;
		const float yPositionAmount = (ScreenHeight() - self.toucan.position.y) / 2;
		self.toucan.item.body->ApplyForceToCenter({0, yAmount + yPositionAmount}, true);
		
		// move toucan towards horizontal center of screen if needed
		auto linearVelocity = self.toucan.item.body->GetLinearVelocity();
		linearVelocity.x = (ScreenWidth() / 2 / kPTMRatio) - self.toucan.item.positionForBox2D.x;
		self.toucan.item.body->SetLinearVelocity(linearVelocity);
	}
	return YES;
}

- (void)ccTouchMoved:(UITouch *)touch withEvent:(UIEvent *)event {
	self.toucan.item.body->ApplyForceToCenter({0, 10}, true);
}

@end
